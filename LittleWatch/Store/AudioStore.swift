import AVFoundation
import Combine
import CoreAudio
import Foundation

@MainActor
final class AudioStore: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var defaultOutputUID: String?
    @Published private(set) var defaultInputUID: String?
    @Published private(set) var outputVolume: Double?
    @Published private(set) var outputMuted = false
    @Published private(set) var volumeControlAvailable = false
    @Published private(set) var muteControlAvailable = false
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var microphonePermissionDenied = false
    @Published var ruleState: AudioRuleState {
        didSet { ruleStore.save(ruleState) }
    }

    var outputs: [AudioDevice] { devices.filter(\.supportsOutput) }
    var inputs: [AudioDevice] { devices.filter(\.supportsInput) }

    private let service = CoreAudioDeviceService()
    private let ruleStore: AudioRuleStore
    private let levelMeter = InputLevelMeter()
    private var levelTimer: Timer?

    init(ruleStore: AudioRuleStore = AudioRuleStore()) {
        self.ruleStore = ruleStore
        self.ruleState = ruleStore.load()

        service.installListenersIfNeeded()
        service.onDefaultOutputChanged = { [weak self] in
            self?.handleDefaultDeviceChange(.output)
        }
        service.onDefaultInputChanged = { [weak self] in
            self?.handleDefaultDeviceChange(.input)
        }
        service.onDeviceListChanged = { [weak self] in
            self?.refreshDevices()
        }

        refreshDevices()
        // 冷启动时默认设备可能已落在禁止集合里（如重启后蓝牙先连），
        // 没有属性变化事件也要跑一次纠正检查。
        handleDefaultDeviceChange(.output)
        handleDefaultDeviceChange(.input)
    }

    // MARK: - Device state

    func currentDevice(for direction: AudioDeviceDirection) -> AudioDevice? {
        let uid = switch direction {
        case .output: defaultOutputUID
        case .input: defaultInputUID
        }
        return devices.first { $0.uid == uid }
    }

    func refreshDevices() {
        devices = service.devices()
        refreshDefaults(recordManualSelections: true)
        refreshVolume()
    }

    /// 面板每次打开时重新枚举，保证拔插后状态是新的。
    func refreshForPanelDisplay() {
        refreshDevices()
        startLevelUpdatesIfPermitted()
    }

    // MARK: - User actions

    func selectOutput(_ device: AudioDevice) {
        guard device.supportsOutput, !ruleState.forbiddenOutputUIDs.contains(device.uid) else { return }
        ruleState = ruleState.recordingManualSelection(device.uid, for: .output)
        service.setDefaultDevice(device.id, for: .output)
        refreshDefaults(recordManualSelections: false)
        refreshVolume()
    }

    func selectInput(_ device: AudioDevice) {
        guard device.supportsInput, !ruleState.forbiddenInputUIDs.contains(device.uid) else { return }
        ruleState = ruleState.recordingManualSelection(device.uid, for: .input)
        service.setDefaultDevice(device.id, for: .input)
        refreshDefaults(recordManualSelections: false)
    }

    func setForbidden(_ forbidden: Bool, uid: String, direction: AudioDeviceDirection) {
        ruleState = forbidden
            ? ruleState.forbidding(uid, for: direction)
            : ruleState.allowing(uid, for: direction)
        // 解锁不会自动切默认设备；下次该设备被禁后再抢默认时才会被纠正。
        handleDefaultDeviceChange(direction)
    }

    func setVolume(_ value: Double) {
        guard let device = currentDevice(for: .output) else { return }
        outputVolume = min(max(value, 0), 1)
        service.setOutputVolume(deviceID: device.id, value)
    }

    /// 滑块拖动结束后回读设备真实音量，防止设备实际值与界面漂移。
    func refreshForVolumeSync() {
        refreshVolume()
    }

    func setMuted(_ muted: Bool) {
        guard let device = currentDevice(for: .output) else { return }
        outputMuted = muted
        service.setOutputMuted(deviceID: device.id, muted)
    }

    func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermissionDenied = false
            startLevelUpdatesIfPermitted()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.microphonePermissionDenied = !granted
                        if granted {
                            self?.startLevelUpdatesIfPermitted()
                        }
                    }
                }
            }
        default:
            microphonePermissionDenied = true
        }
    }

    func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
        levelMeter.stop()
        inputLevel = 0
    }

    // MARK: - Internal

    private func refreshDefaults(recordManualSelections: Bool) {
        let availableUIDs = Set(devices.map(\.uid))

        let newOutputUID = service.defaultDeviceID(for: .output).flatMap { id in
            devices.first { $0.id == id }?.uid
        }
        applyDefaultUID(
            newOutputUID,
            direction: .output,
            availableUIDs: availableUIDs,
            recordManualSelection: recordManualSelections
        )

        let newInputUID = service.defaultDeviceID(for: .input).flatMap { id in
            devices.first { $0.id == id }?.uid
        }
        applyDefaultUID(
            newInputUID,
            direction: .input,
            availableUIDs: availableUIDs,
            recordManualSelection: recordManualSelections
        )
    }

    private func applyDefaultUID(
        _ uid: String?,
        direction: AudioDeviceDirection,
        availableUIDs: Set<String>,
        recordManualSelection: Bool
    ) {
        let forbidden = ruleState.forbiddenUIDs(for: direction)
        if recordManualSelection {
            let recorded = AudioRuleEngine.recordedManualSelection(
                previousUID: ruleState.lastManualUID(for: direction),
                newDefaultUID: uid,
                forbiddenUIDs: forbidden
            )
            if recorded != ruleState.lastManualUID(for: direction) {
                ruleState = ruleState.recordingManualSelection(recorded, for: direction)
            }
        }
        switch direction {
        case .output: defaultOutputUID = uid
        case .input: defaultInputUID = uid
        }
    }

    /// 默认设备变化：落进禁止集合就切回上次手选（不存在回退内置），否则记为手选。
    private func handleDefaultDeviceChange(_ direction: AudioDeviceDirection) {
        refreshDevices()

        let currentUID = switch direction {
        case .output: defaultOutputUID
        case .input: defaultInputUID
        }
        let availableUIDs = Set(devices.map(\.uid))
        let fallback = service.fallbackDeviceID(for: direction, in: devices)?.uid

        let target = AudioRuleEngine.correctionTarget(for: .init(
            currentDefaultUID: currentUID,
            forbiddenUIDs: ruleState.forbiddenUIDs(for: direction),
            lastManualUID: ruleState.lastManualUID(for: direction),
            fallbackUID: fallback,
            availableUIDs: availableUIDs
        ))

        guard let target, let device = devices.first(where: { $0.uid == target }) else { return }
        service.setDefaultDevice(device.id, for: direction)
        ruleState = ruleState.recordingManualSelection(target, for: direction)
        refreshDefaults(recordManualSelections: false)
        if direction == .output {
            refreshVolume()
        }
    }

    private func refreshVolume() {
        guard let device = currentDevice(for: .output) else {
            volumeControlAvailable = false
            muteControlAvailable = false
            outputVolume = nil
            outputMuted = false
            return
        }
        let control = service.outputVolumeControl(deviceID: device.id)
        volumeControlAvailable = control.supportsVolume
        muteControlAvailable = control.supportsMute
        outputVolume = control.supportsVolume ? service.outputVolume(deviceID: device.id) : nil
        outputMuted = control.supportsMute ? (service.outputMuted(deviceID: device.id) ?? false) : false
    }

    private func startLevelUpdatesIfPermitted() {
        guard let device = currentDevice(for: .input) else {
            stopLevelUpdates()
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            microphonePermissionDenied =
                AVCaptureDevice.authorizationStatus(for: .audio) == .denied
            return
        }
        microphonePermissionDenied = false

        do {
            try levelMeter.start(deviceID: device.id)
        } catch {
            stopLevelUpdates()
            return
        }

        if levelTimer == nil {
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.inputLevel = self.levelMeter.currentPeak()
                }
            }
        }
    }
}

import CoreAudio
import Foundation

@MainActor
final class CoreAudioDeviceService {
    var onDefaultOutputChanged: (() -> Void)?
    var onDefaultInputChanged: (() -> Void)?
    var onDeviceListChanged: (() -> Void)?

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let callbackQueue = DispatchQueue(label: "com.littlewatch.coreaudio.events")
    private var listenersInstalled = false

    struct OutputVolumeControl: Equatable {
        let supportsVolume: Bool
        let supportsMute: Bool
        let usesMasterElement: Bool
    }

    // MARK: - Device enumeration

    func devices() -> [AudioDevice] {
        guard let deviceIDs: [AudioObjectID] = readArrayProperty(
            systemObject,
            kAudioHardwarePropertyDevices
        ) else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard let uid = readStringProperty(
                deviceID,
                kAudioDevicePropertyDeviceUID
            ) else { return nil }

            let outputChannels = channelCount(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput)
            let inputChannels = channelCount(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput)
            guard outputChannels > 0 || inputChannels > 0 else { return nil }

            return AudioDevice(
                id: deviceID,
                uid: uid,
                name: readStringProperty(deviceID, kAudioObjectPropertyName) ?? "未知设备",
                sampleRate: readNumericProperty(deviceID, kAudioDevicePropertyNominalSampleRate, Float64.self),
                outputChannelCount: outputChannels,
                inputChannelCount: inputChannels
            )
        }
    }

    func defaultDeviceID(for direction: AudioDeviceDirection) -> AudioObjectID? {
        let selector: AudioObjectPropertySelector = switch direction {
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        case .input: kAudioHardwarePropertyDefaultInputDevice
        }
        let deviceID = readNumericProperty(systemObject, selector, AudioObjectID.self)
        return deviceID.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    func setDefaultDevice(_ deviceID: AudioObjectID, for direction: AudioDeviceDirection) {
        let selector: AudioObjectPropertySelector = switch direction {
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        case .input: kAudioHardwarePropertyDefaultInputDevice
        }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = deviceID
        withUnsafeMutablePointer(to: &value) { pointer in
            _ = AudioObjectSetPropertyData(
                systemObject, &address, 0, nil,
                UInt32(MemoryLayout<AudioObjectID>.size), pointer
            )
        }
    }

    /// 内置扬声器/麦克风：优先用 transportType == builtIn 判断，找不到再按名称兜底。
    func fallbackDeviceID(for direction: AudioDeviceDirection, in devices: [AudioDevice]) -> AudioDevice? {
        let deviceIDs = devices.map { $0.id }
        let builtinCandidates = deviceIDs.filter { deviceID in
            readTransportType(deviceID) == kAudioDeviceTransportTypeBuiltIn
        }
        for deviceID in builtinCandidates {
            if let device = devices.first(where: { $0.id == deviceID }), device.supports(direction) {
                return device
            }
        }
        return devices.first {
            $0.supports(direction) && $0.name.contains(direction.fallbackDeviceNameContains)
        }
    }

    // MARK: - Volume / mute (output scope)

    func outputVolumeControl(deviceID: AudioObjectID) -> OutputVolumeControl {
        OutputVolumeControl(
            supportsVolume: isVolumeSettable(deviceID, kAudioDevicePropertyVolumeScalar, preferredElement(deviceID)),
            supportsMute: isVolumeSettable(deviceID, kAudioDevicePropertyMute, preferredMuteElement(deviceID)),
            usesMasterElement: preferredElement(deviceID) == kAudioObjectPropertyElementMain
        )
    }

    func outputVolume(deviceID: AudioObjectID) -> Double? {
        let element = preferredElement(deviceID)
        if element == kAudioObjectPropertyElementMain {
            return readNumericProperty(
                deviceID, kAudioDevicePropertyVolumeScalar, Float32.self,
                scope: kAudioObjectPropertyScopeOutput, element: element
            ).map { Double($0) }
        }
        let values = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)].compactMap {
            readNumericProperty(
                deviceID, kAudioDevicePropertyVolumeScalar, Float32.self,
                scope: kAudioObjectPropertyScopeOutput, element: $0
            )
        }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +) / Float32(values.count))
    }

    func setOutputVolume(deviceID: AudioObjectID, _ value: Double) {
        let clamped = Float32(min(max(value, 0), 1))
        let element = preferredElement(deviceID)
        if element == kAudioObjectPropertyElementMain {
            writeVolume(deviceID, kAudioDevicePropertyVolumeScalar, element, clamped)
        } else {
            for candidate in [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
                writeVolume(deviceID, kAudioDevicePropertyVolumeScalar, candidate, clamped)
            }
        }
    }

    func outputMuted(deviceID: AudioObjectID) -> Bool? {
        readNumericProperty(
            deviceID, kAudioDevicePropertyMute, UInt32.self,
            scope: kAudioObjectPropertyScopeOutput, element: preferredMuteElement(deviceID)
        ).map { $0 != 0 }
    }

    func setOutputMuted(deviceID: AudioObjectID, _ muted: Bool) {
        let element = preferredMuteElement(deviceID)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        var value: UInt32 = muted ? 1 : 0
        withUnsafeMutablePointer(to: &value) { pointer in
            _ = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), pointer
            )
        }
    }

    // MARK: - Listeners

    func installListenersIfNeeded() {
        guard !listenersInstalled else { return }
        listenersInstalled = true

        installListener(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.onDefaultOutputChanged?()
        }
        installListener(kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
            self?.onDefaultInputChanged?()
        }
        installListener(kAudioHardwarePropertyDevices) { [weak self] in
            self?.onDeviceListChanged?()
        }
    }

    private func installListener(
        _ selector: AudioObjectPropertySelector,
        onMainActor fire: @escaping () -> Void
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObject, &address, callbackQueue) { _, _ in
            Task { @MainActor in fire() }
        }
    }

    // MARK: - Property access helpers

    private func readArrayProperty(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr, size > 0 else {
            return nil
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        var values = [AudioObjectID](repeating: 0, count: count)
        return values.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress,
                  AudioObjectGetPropertyData(
                    objectID, &address, 0, nil, &size, baseAddress
                  ) == noErr else { return nil }
            return Array(buffer)
        }
    }

    private func readNumericProperty<T: Numeric>(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ type: T.Type,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: element
        )
        var value = T.zero
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer) == noErr else {
                return nil
            }
            return pointer.pointee
        }
    }

    private func readStringProperty(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var string: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &string) == noErr else {
            return nil
        }
        return string?.takeRetainedValue() as String?
    }

    private func channelCount(
        deviceID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }

        var total = 0
        for buffer in UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)) {
            total += Int(buffer.mNumberChannels)
        }
        return total
    }

    private func readTransportType(_ deviceID: AudioObjectID) -> UInt32 {
        readNumericProperty(deviceID, kAudioDevicePropertyTransportType, UInt32.self) ?? 0
    }

    /// 音量元素探测：先试 master（element 0），不支持再试左声道（element 1，写入时连同 element 2）。
    private func preferredElement(_ deviceID: AudioObjectID) -> AudioObjectPropertyElement {
        if isVolumeSettable(deviceID, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain) {
            return kAudioObjectPropertyElementMain
        }
        if isVolumeSettable(deviceID, kAudioDevicePropertyVolumeScalar, AudioObjectPropertyElement(1)) {
            return AudioObjectPropertyElement(1)
        }
        return kAudioObjectPropertyElementMain
    }

    private func preferredMuteElement(_ deviceID: AudioObjectID) -> AudioObjectPropertyElement {
        if isVolumeSettable(deviceID, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain) {
            return kAudioObjectPropertyElementMain
        }
        return AudioObjectPropertyElement(1)
    }

    private func isVolumeSettable(
        _ deviceID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else {
            return false
        }
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
    }

    private func writeVolume(
        _ deviceID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ element: AudioObjectPropertyElement,
        _ value: Float32
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        var mutableValue = value
        withUnsafeMutablePointer(to: &mutableValue) { pointer in
            _ = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil,
                UInt32(MemoryLayout<Float32>.size), pointer
            )
        }
    }
}

private extension AudioDevice {
    func supports(_ direction: AudioDeviceDirection) -> Bool {
        switch direction {
        case .output: supportsOutput
        case .input: supportsInput
        }
    }
}

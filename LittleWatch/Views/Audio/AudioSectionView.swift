import AudioToolbox
import os
import SwiftUI

struct AudioSectionView: View {
    @ObservedObject var store: AudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            deviceList(
                title: "输出",
                devices: store.outputs,
                currentUID: store.defaultOutputUID,
                forbiddenUIDs: store.ruleState.forbiddenOutputUIDs,
                direction: .output
            )

            volumeSection

            Divider().overlay(LittleWatchTheme.hairline)

            deviceList(
                title: "输入",
                devices: store.inputs,
                currentUID: store.defaultInputUID,
                forbiddenUIDs: store.ruleState.forbiddenInputUIDs,
                direction: .input
            )

            levelSection
        }
        .padding(12)
        .background(LittleWatchTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LittleWatchTheme.hairline, lineWidth: 1)
        }
    }

    private func deviceList(
        title: String,
        devices: [AudioDevice],
        currentUID: String?,
        forbiddenUIDs: Set<String>,
        direction: AudioDeviceDirection
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LittleWatchTheme.secondaryText)
                .padding(.bottom, 4)

            ForEach(devices) { device in
                AudioDeviceRow(
                    device: device,
                    isCurrent: device.uid == currentUID,
                    isForbidden: forbiddenUIDs.contains(device.uid),
                    onSelect: {
                        switch direction {
                        case .output: store.selectOutput(device)
                        case .input: store.selectInput(device)
                        }
                    },
                    onToggleForbidden: { forbidden in
                        store.setForbidden(forbidden, uid: device.uid, direction: direction)
                    }
                )
            }
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("音量")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
                Spacer()
                Text(volumeText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }

            Slider(
                value: Binding(
                    get: { store.outputVolume ?? 0 },
                    set: { store.setVolume($0) }
                ),
                onEditingChanged: { editing in
                    if !editing {
                        store.refreshForVolumeSync()
                    }
                }
            )
            .controlSize(.mini)
            .disabled(!store.volumeControlAvailable)
            .opacity(store.volumeControlAvailable ? 1 : 0.35)

            if store.muteControlAvailable {
                Toggle(isOn: Binding(
                    get: { store.outputMuted },
                    set: { store.setMuted($0) }
                )) {
                    Text("静音")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.secondaryText)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    private var volumeText: String {
        store.volumeControlAvailable
            ? "\(Int(((store.outputVolume ?? 0) * 100).rounded()))%"
            : "不支持"
    }

    private var levelSection: some View {
        HStack(spacing: 8) {
            Text("电平")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LittleWatchTheme.secondaryText)
                .help(store.microphonePermissionDenied ? "需要麦克风权限" : "")
            Spacer()
            if store.microphonePermissionDenied {
                Text("无麦克风权限")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.amber.opacity(0.85))
            } else {
                InputLevelBar(level: store.inputLevel)
                    .frame(width: 120, height: 14)
            }
        }
        .padding(.top, 4)
    }
}

private struct AudioDeviceRow: View {
    let device: AudioDevice
    let isCurrent: Bool
    let isForbidden: Bool
    let onSelect: () -> Void
    let onToggleForbidden: (Bool) -> Void

    @State private var isHovered = false
    @State private var showButton = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isForbidden ? "minus.circle" : (isCurrent ? "circle.inset.filled" : "circle"))
                .font(.system(size: 11))
                .foregroundStyle(isForbidden ? LittleWatchTheme.amber : LittleWatchTheme.signal)
                .frame(width: 14)

            Text(device.name)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isForbidden ? LittleWatchTheme.secondaryText : LittleWatchTheme.primaryText)
                .lineLimit(1)

            Spacer()

            if isForbidden {
                Text("已禁")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.amber.opacity(0.85))
            } else if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LittleWatchTheme.signal)
            }

            restoreOrForbidButton
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 26)
        .contentShape(Rectangle())
        .opacity(isForbidden ? 0.75 : 1)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isHovered && !isForbidden ? 0.05 : 0))
        )
        .onHover { hovering in
            isHovered = hovering
            withAnimation(.easeOut(duration: 0.12)) {
                showButton = hovering
            }
        }
        .onTapGesture {
            if !isForbidden {
                onSelect()
            }
        }
        .help(isForbidden ? "已禁用" : device.tooltip)
    }

    @ViewBuilder
    private var restoreOrForbidButton: some View {
        let symbol = isForbidden ? "arrow.uturn.backward.circle" : "minus.circle"
        let helpText = isForbidden ? "恢复此设备" : "禁止此设备"
        let tint = isForbidden ? LittleWatchTheme.signal : LittleWatchTheme.amber

        Button {
            onToggleForbidden(!isForbidden)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(showButton ? 1 : 0)
        .disabled(!showButton)
        .help(helpText)
    }
}

private struct InputLevelBar: View {    let level: Double

    private var litCount: Int {
        Int(min(max(level, 0), 1) * Double(Self.barCount))
    }

    private static let barCount = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(color(for: index))
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.08), value: litCount)
    }

    private func color(for index: Int) -> Color {
        guard index < litCount else { return Color.white.opacity(0.08) }
        let fraction = Double(index) / Double(Self.barCount - 1)
        if fraction > 0.85 { return Color(red: 1.0, green: 0.36, blue: 0.32) }
        if fraction > 0.6 { return LittleWatchTheme.amber }
        return LittleWatchTheme.signal
    }
}

/// 系统音量调节反馈音：与按键调音量时的 tick 同源（BezelServices volume.aiff）。
/// 跟随系统「调整音量时播放反馈音」设置（com.apple.sound.beep.feedback，缺省开启）。
enum VolumeFeedbackSound {
    private static let cachedSound = OSAllocatedUnfairLock<SystemSoundID>(initialState: 0)
    private static let lastPlayed = OSAllocatedUnfairLock<Date>(initialState: .distantPast)
    private static let minInterval: TimeInterval = 0.15

    /// 拖动过程中连续写入音量时按最小间隔节流，避免连环响。
    static func playThrottled() {
        let now = Date()
        let shouldPlay = lastPlayed.withLock { state -> Bool in
            guard now.timeIntervalSince(state) >= minInterval else { return false }
            state = now
            return true
        }
        guard shouldPlay else { return }
        play()
    }

    static func play() {
        if let value = UserDefaults.standard.object(forKey: "com.apple.sound.beep.feedback") as? Int,
           value == 0 {
            return
        }
        let sound = cachedSound.withLock { state -> SystemSoundID in
            if state != 0 { return state }
            let url = URL(fileURLWithPath: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff") as CFURL
            var id = SystemSoundID(0)
            guard AudioServicesCreateSystemSoundID(url, &id) == noErr else { return 0 }
            state = id
            return id
        }
        guard sound != 0 else { return }
        AudioServicesPlaySystemSound(sound)
    }
}

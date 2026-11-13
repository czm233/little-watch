import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let sampleRate: Double?
    let outputChannelCount: Int
    let inputChannelCount: Int

    var supportsOutput: Bool { outputChannelCount > 0 }
    var supportsInput: Bool { inputChannelCount > 0 }

    var tooltip: String {
        var parts: [String] = []
        if let sampleRate {
            let kilohertz = sampleRate / 1_000
            let text = kilohertz == kilohertz.rounded()
                ? String(format: "%.0f", kilohertz)
                : String(format: "%.1f", kilohertz)
            parts.append("\(text) kHz")
        }
        if supportsOutput { parts.append("\(outputChannelCount) 出") }
        if supportsInput { parts.append("\(inputChannelCount) 入") }
        return parts.joined(separator: " · ")
    }
}

enum AudioDeviceDirection: String, CaseIterable, Sendable {
    case output
    case input

    var fallbackDeviceNameContains: String {
        switch self {
        case .output: "扬声器"
        case .input: "麦克风"
        }
    }
}

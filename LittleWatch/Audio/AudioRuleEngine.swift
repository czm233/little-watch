import Foundation

/// 规则状态：禁止集合与上次手选设备都按 UID 持久化。
struct AudioRuleState: Codable, Equatable, Sendable {
    var forbiddenOutputUIDs: Set<String> = []
    var forbiddenInputUIDs: Set<String> = []
    var lastManualOutputUID: String?
    var lastManualInputUID: String?

    func forbiddenUIDs(for direction: AudioDeviceDirection) -> Set<String> {
        switch direction {
        case .output: forbiddenOutputUIDs
        case .input: forbiddenInputUIDs
        }
    }

    func lastManualUID(for direction: AudioDeviceDirection) -> String? {
        switch direction {
        case .output: lastManualOutputUID
        case .input: lastManualInputUID
        }
    }

    func forbidding(_ uid: String, for direction: AudioDeviceDirection) -> AudioRuleState {
        var next = self
        switch direction {
        case .output: next.forbiddenOutputUIDs.insert(uid)
        case .input: next.forbiddenInputUIDs.insert(uid)
        }
        return next
    }

    func allowing(_ uid: String, for direction: AudioDeviceDirection) -> AudioRuleState {
        var next = self
        switch direction {
        case .output: next.forbiddenOutputUIDs.remove(uid)
        case .input: next.forbiddenInputUIDs.remove(uid)
        }
        return next
    }

    func recordingManualSelection(_ uid: String?, for direction: AudioDeviceDirection) -> AudioRuleState {
        var next = self
        switch direction {
        case .output: next.lastManualOutputUID = uid
        case .input: next.lastManualInputUID = uid
        }
        return next
    }
}

/// 纯逻辑：默认设备变化时的纠正决策。
enum AudioRuleEngine {
    struct CorrectionContext: Equatable, Sendable {
        let currentDefaultUID: String?
        let forbiddenUIDs: Set<String>
        let lastManualUID: String?
        let fallbackUID: String?
        let availableUIDs: Set<String>
    }

    /// 默认设备落入禁止集合时返回应切回的目标 UID；无需干预返回 nil。
    /// 优先上次手选设备，其次内置设备；候选必须在线、未被禁、且不是当前设备。
    static func correctionTarget(for context: CorrectionContext) -> String? {
        guard let current = context.currentDefaultUID,
              context.forbiddenUIDs.contains(current)
        else { return nil }

        let candidates = [context.lastManualUID, context.fallbackUID].compactMap { $0 }
        for candidate in candidates
        where candidate != current
            && context.availableUIDs.contains(candidate)
            && !context.forbiddenUIDs.contains(candidate) {
            return candidate
        }
        return nil
    }

    /// 判断一次默认设备变化是否算「用户手选」：落入禁止集合的变化视为抢占，不更新手选记录。
    static func recordedManualSelection(
        previousUID: String?,
        newDefaultUID: String?,
        forbiddenUIDs: Set<String>
    ) -> String? {
        guard let newDefaultUID, !forbiddenUIDs.contains(newDefaultUID) else {
            return previousUID
        }
        return newDefaultUID
    }
}

/// UserDefaults 持久化。
struct AudioRuleStore {
    private let defaults: UserDefaults
    private let key = "littlewatch.audio.rules.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AudioRuleState {
        guard
            let data = defaults.data(forKey: key),
            let state = try? JSONDecoder().decode(AudioRuleState.self, from: data)
        else {
            return AudioRuleState()
        }
        return state
    }

    func save(_ state: AudioRuleState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

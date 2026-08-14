import Combine
import Foundation
import ServiceManagement

enum LaunchAtLoginRegistrationStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isRequested: Bool {
        self == .enabled || self == .requiresApproval
    }
}

protocol LaunchAtLoginServicing {
    var status: LaunchAtLoginRegistrationStatus { get }

    func register() throws
    func unregister() throws
    func openSystemSettings()
}

struct SystemLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginRegistrationStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct LaunchAtLoginPreferenceStore {
    private let defaults: UserDefaults
    private let key = "littlewatch.launchAtLogin.enabled.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        defaults.bool(forKey: key)
    }

    func save(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: key)
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isUpdating = false
    @Published private(set) var registrationStatus: LaunchAtLoginRegistrationStatus = .notRegistered
    @Published private(set) var errorMessage: String?

    private let service: any LaunchAtLoginServicing
    private let preferenceStore: LaunchAtLoginPreferenceStore

    init(
        service: any LaunchAtLoginServicing = SystemLaunchAtLoginService(),
        preferenceStore: LaunchAtLoginPreferenceStore = LaunchAtLoginPreferenceStore()
    ) {
        self.service = service
        self.preferenceStore = preferenceStore

        refreshStatus(reconcileStoredPreference: true)
    }

    var statusDetail: String {
        if let errorMessage {
            return errorMessage
        }

        return switch registrationStatus {
        case .notRegistered:
            "关闭时不会随登录自动运行"
        case .enabled:
            "已启用，将在登录 macOS 后自动运行"
        case .requiresApproval:
            "需要在“系统设置 > 通用 > 登录项”中批准"
        case .notFound:
            "系统无法找到当前应用的登录项"
        }
    }

    var requiresApproval: Bool {
        registrationStatus == .requiresApproval
    }

    func setEnabled(_ newValue: Bool) {
        guard newValue != isEnabled || errorMessage != nil else { return }

        let previousValue = isEnabled
        errorMessage = nil
        isUpdating = true
        defer { isUpdating = false }

        do {
            if newValue {
                if !service.status.isRequested {
                    try service.register()
                }
            } else if service.status.isRequested {
                try service.unregister()
            }

            let updatedStatus = service.status
            guard newValue == updatedStatus.isRequested else {
                throw LaunchAtLoginError.stateDidNotChange
            }

            registrationStatus = updatedStatus
            isEnabled = newValue
            preferenceStore.save(newValue)
        } catch {
            let currentStatus = service.status
            registrationStatus = currentStatus
            isEnabled = currentStatus.isRequested
            preferenceStore.save(isEnabled)

            if isEnabled == newValue {
                errorMessage = nil
            } else {
                isEnabled = previousValue
                preferenceStore.save(previousValue)
                errorMessage = "设置失败：\(error.localizedDescription)"
            }
        }
    }

    func refreshStatus() {
        refreshStatus(reconcileStoredPreference: false)
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }

    private func refreshStatus(reconcileStoredPreference: Bool) {
        errorMessage = nil
        registrationStatus = service.status

        if reconcileStoredPreference,
           preferenceStore.load(),
           registrationStatus == .notRegistered {
            do {
                try service.register()
                registrationStatus = service.status
            } catch {
                errorMessage = "无法恢复登录启动：\(error.localizedDescription)"
            }
        }

        isEnabled = registrationStatus.isRequested
        preferenceStore.save(isEnabled)
    }
}

private enum LaunchAtLoginError: LocalizedError {
    case stateDidNotChange

    var errorDescription: String? {
        "系统未接受此项更改"
    }
}

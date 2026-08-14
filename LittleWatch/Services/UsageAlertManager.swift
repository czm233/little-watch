@preconcurrency import UserNotifications
import Foundation

struct UsageAlertConfiguration: Codable, Equatable, Sendable {
    var dailyBudgetUSD: Double?
    var budgetAlertEnabled: Bool
    var spikeAlertEnabled: Bool

    static let `default` = UsageAlertConfiguration(
        dailyBudgetUSD: nil,
        budgetAlertEnabled: false,
        spikeAlertEnabled: false
    )

    var normalizedDailyBudgetUSD: Double? {
        guard let dailyBudgetUSD, dailyBudgetUSD.isFinite, dailyBudgetUSD > 0 else {
            return nil
        }
        return dailyBudgetUSD
    }
}

enum NotificationPermissionState: Equatable, Sendable {
    case unknown
    case authorized
    case denied

    var canDeliver: Bool { self == .authorized }
}

struct UsageAlertConfigurationStore {
    private let defaults: UserDefaults
    private let configurationKey = "littlewatch.usage-alert.configuration.v1"
    private let deliveryStateKey = "littlewatch.usage-alert.delivery-state.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UsageAlertConfiguration {
        guard
            let data = defaults.data(forKey: configurationKey),
            let configuration = try? JSONDecoder().decode(UsageAlertConfiguration.self, from: data)
        else {
            return .default
        }
        return configuration
    }

    func save(_ configuration: UsageAlertConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: configurationKey)
    }

    func loadDeliveryState() -> UsageAlertDeliveryState {
        guard
            let data = defaults.data(forKey: deliveryStateKey),
            let state = try? JSONDecoder().decode(UsageAlertDeliveryState.self, from: data)
        else {
            return .empty
        }
        return state
    }

    func saveDeliveryState(_ state: UsageAlertDeliveryState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: deliveryStateKey)
    }
}

struct UsageAlertDeliveryState: Codable, Equatable, Sendable {
    var lastBudgetAlertDay: String?
    var lastTPMAlertAt: Date?
    var lastRPMAlertAt: Date?

    static let empty = UsageAlertDeliveryState(
        lastBudgetAlertDay: nil,
        lastTPMAlertAt: nil,
        lastRPMAlertAt: nil
    )
}

enum UsageAlertDelivery: Equatable, Sendable {
    case budget(dayIdentifier: String, currentCost: Double, budget: Double)
    case spike(UsageSpikeEvent)

    var identifier: String {
        switch self {
        case let .budget(dayIdentifier, _, _):
            "littlewatch.budget.\(dayIdentifier)"
        case let .spike(event):
            "littlewatch.spike.\(event.metric.rawValue).\(Int(event.detectedAt.timeIntervalSince1970))"
        }
    }

    var title: String {
        switch self {
        case .budget:
            "今日预算已超出"
        case let .spike(event):
            event.metric == .tokensPerMinute ? "TPM 用量突增" : "RPM 请求突增"
        }
    }

    var body: String {
        switch self {
        case let .budget(_, currentCost, budget):
            return "今日消费 \(Self.currency(currentCost))，已超过 \(Self.currency(budget)) 的预算。"
        case let .spike(event):
            let metric = event.metric == .tokensPerMinute ? "TPM" : "RPM"
            let current = event.currentValue.formatted(.number.precision(.fractionLength(0...1)))
            let multiple = event.multiple.formatted(.number.precision(.fractionLength(1)))
            return "\(metric) 当前为 \(current)，约是近期基线的 \(multiple) 倍。"
        }
    }

    private static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

enum UsageAlertEvaluator {
    static let spikeCooldown: TimeInterval = 15 * 60
    static let maximumSpikeAge: TimeInterval = 20 * 60

    static func pendingDeliveries(
        snapshot: MetricSnapshot,
        configuration: UsageAlertConfiguration,
        state: UsageAlertDeliveryState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [UsageAlertDelivery] {
        var deliveries: [UsageAlertDelivery] = []

        if configuration.budgetAlertEnabled,
           let budget = configuration.normalizedDailyBudgetUSD,
           snapshot.costUSD >= budget {
            let dayIdentifier = dayIdentifier(for: now, calendar: calendar)
            if state.lastBudgetAlertDay != dayIdentifier {
                deliveries.append(
                    .budget(
                        dayIdentifier: dayIdentifier,
                        currentCost: snapshot.costUSD,
                        budget: budget
                    )
                )
            }
        }

        if configuration.spikeAlertEnabled,
           let spike = snapshot.usageSpike,
           now.timeIntervalSince(spike.detectedAt) >= 0,
           now.timeIntervalSince(spike.detectedAt) <= maximumSpikeAge {
            let lastAlertAt = spike.metric == .tokensPerMinute
                ? state.lastTPMAlertAt
                : state.lastRPMAlertAt
            if lastAlertAt.map({ now.timeIntervalSince($0) >= spikeCooldown }) ?? true {
                deliveries.append(.spike(spike))
            }
        }

        return deliveries
    }

    static func record(
        _ delivery: UsageAlertDelivery,
        in state: inout UsageAlertDeliveryState,
        deliveredAt: Date
    ) {
        switch delivery {
        case let .budget(dayIdentifier, _, _):
            state.lastBudgetAlertDay = dayIdentifier
        case let .spike(event):
            if event.metric == .tokensPerMinute {
                state.lastTPMAlertAt = deliveredAt
            } else {
                state.lastRPMAlertAt = deliveredAt
            }
        }
    }

    private static func dayIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

@MainActor
protocol UsageNotificationDelivering {
    func permissionState() async -> NotificationPermissionState
    func requestPermission() async -> NotificationPermissionState
    func deliver(_ alert: UsageAlertDelivery) async throws
}

@MainActor
struct SystemUsageNotificationService: UsageNotificationDelivering {
    private let center = UNUserNotificationCenter.current()

    func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestPermission() async -> NotificationPermissionState {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return .denied
        }
        return await permissionState()
    }

    func deliver(_ alert: UsageAlertDelivery) async throws {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: alert.identifier,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationPermissionState {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .unknown
        @unknown default:
            .unknown
        }
    }
}

@MainActor
final class UsageAlertManager {
    private let notificationService: any UsageNotificationDelivering
    private let store: UsageAlertConfigurationStore
    private var deliveryState: UsageAlertDeliveryState
    private var isEvaluating = false

    init(
        notificationService: any UsageNotificationDelivering = SystemUsageNotificationService(),
        store: UsageAlertConfigurationStore = UsageAlertConfigurationStore()
    ) {
        self.notificationService = notificationService
        self.store = store
        deliveryState = store.loadDeliveryState()
    }

    func permissionState() async -> NotificationPermissionState {
        await notificationService.permissionState()
    }

    func requestPermission() async -> NotificationPermissionState {
        await notificationService.requestPermission()
    }

    func resetDailyBudgetAlert() {
        deliveryState.lastBudgetAlertDay = nil
        store.saveDeliveryState(deliveryState)
    }

    func evaluate(
        snapshot: MetricSnapshot,
        configuration: UsageAlertConfiguration,
        now: Date = Date()
    ) async {
        guard !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        guard await notificationService.permissionState().canDeliver else { return }
        let deliveries = UsageAlertEvaluator.pendingDeliveries(
            snapshot: snapshot,
            configuration: configuration,
            state: deliveryState,
            now: now
        )

        for delivery in deliveries {
            do {
                try await notificationService.deliver(delivery)
                UsageAlertEvaluator.record(
                    delivery,
                    in: &deliveryState,
                    deliveredAt: now
                )
                store.saveDeliveryState(deliveryState)
            } catch {
                // A later refresh will retry because failed deliveries are not recorded.
            }
        }
    }
}

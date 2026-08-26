import Combine
import Foundation

private enum SourceRefreshResult: Equatable {
    case succeeded
    case retryableFailure
    case terminalFailure
    case skipped

    var shouldContinuePolling: Bool {
        self == .succeeded || self == .retryableFailure
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var configuration: AppConfiguration {
        didSet {
            configurationStore.save(configuration)
            rotationIndex = 0
            scheduleRotation()
        }
    }
    @Published private(set) var snapshot: MetricSnapshot
    @Published private(set) var dailyUsageCounterReset: DailyUsageCounterReset?
    @Published private(set) var systemSnapshot: SystemMetricsSnapshot = .empty
    @Published private(set) var refreshState: RefreshState = .idle
    @Published private(set) var quotaRefreshState: QuotaRefreshState = .idle
    @Published private(set) var quotaRefreshCooldownRemainingSeconds = 0
    @Published private(set) var quotaRemainingPercent: Double?
    @Published private(set) var quotaLastUpdatedAt: Date?
    @Published private(set) var quotaResetAt: Date?
    @Published private(set) var sourceConnectionState: SourceConnectionState = .needsCredential
    @Published private(set) var hasStoredCredential = false
    @Published private(set) var sourceConfiguration: SourceConfiguration
    @Published var alertConfiguration: UsageAlertConfiguration {
        didSet {
            alertConfigurationStore.save(alertConfiguration)
            Task { [weak self] in
                await self?.evaluateUsageAlerts()
            }
        }
    }
    @Published private(set) var notificationPermissionState: NotificationPermissionState = .unknown

    let sourceName = "CPA Usage Keeper"

    private var source: CPAUsageKeeperSource?
    private var quotaRefreshSource: CPAQuotaRefreshSource?
    private let configurationStore: ConfigurationStore
    private let sourceConfigurationStore: SourceConfigurationStore
    private let dailyUsageCounterResetStore: DailyUsageCounterResetStore
    private let alertConfigurationStore: UsageAlertConfigurationStore
    private let usageAlertManager: UsageAlertManager
    private let formatter = MenuBarFormatter()
    private let systemMetricsMonitor = SystemMetricsMonitor()
    private var overviewPollingTask: Task<Void, Never>?
    private var realtimePollingTask: Task<Void, Never>?
    private var systemMetricsTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var quotaPollingTask: Task<Void, Never>?
    private var quotaRefreshCooldownTask: Task<Void, Never>?
    private var quotaRefreshOperationID: UUID?
    private var quotaConfigurationGeneration = 0
    private var rotationIndex = 0
    private var hasConnectedSuccessfully = false
    private var isOverviewRefreshing = false
    private var isRealtimeRefreshing = false
    private var rawSnapshot: MetricSnapshot

    private let overviewRefreshIntervalSeconds = 60
    private let realtimeRefreshIntervalSeconds = 10
    static let quotaRefreshIntervalSeconds = 5 * 60

    init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        sourceConfigurationStore: SourceConfigurationStore = SourceConfigurationStore(),
        dailyUsageCounterResetStore: DailyUsageCounterResetStore = DailyUsageCounterResetStore(),
        alertConfigurationStore: UsageAlertConfigurationStore = UsageAlertConfigurationStore(),
        usageAlertManager: UsageAlertManager? = nil
    ) {
        let loadedSourceConfiguration = sourceConfigurationStore.load()
        let resolvedSourceConfiguration = (try? loadedSourceConfiguration.validatedBaseURL()) == nil
            ? SourceConfiguration.default
            : loadedSourceConfiguration

        self.configurationStore = configurationStore
        self.sourceConfigurationStore = sourceConfigurationStore
        self.dailyUsageCounterResetStore = dailyUsageCounterResetStore
        self.alertConfigurationStore = alertConfigurationStore
        self.usageAlertManager = usageAlertManager ?? UsageAlertManager(store: alertConfigurationStore)
        self.sourceConfiguration = resolvedSourceConfiguration
        self.hasStoredCredential = !resolvedSourceConfiguration.password.isEmpty
        self.configuration = configurationStore.load()
        self.alertConfiguration = alertConfigurationStore.load()
        let initialSnapshot = MetricSnapshot(
            costUSD: 0,
            tokenCount: 0,
            updatedAt: Date()
        )
        self.rawSnapshot = initialSnapshot
        let today = DailyUsageCounter.dayIdentifier()
        let loadedReset = dailyUsageCounterResetStore.load()
        let activeReset = loadedReset?.dayIdentifier == today ? loadedReset : nil
        self.dailyUsageCounterReset = activeReset
        if let loadedReset, loadedReset.dayIdentifier != today {
            dailyUsageCounterResetStore.clear()
        }
        self.snapshot = activeReset.map {
            DailyUsageCounter.adjustedSnapshot(initialSnapshot, using: $0)
        } ?? initialSnapshot
        self.source = try? CPAUsageKeeperSource(configuration: resolvedSourceConfiguration)
        self.quotaRefreshSource = try? CPAQuotaRefreshSource(configuration: resolvedSourceConfiguration)

        Task { [weak self] in
            guard let self else { return }
            notificationPermissionState = await self.usageAlertManager.permissionState()
            await self.prepareSource()
        }
        scheduleSystemMetricsPolling()
        scheduleRotation()
    }

    var menuBarTitle: String {
        formatter.title(
            for: snapshot,
            systemSnapshot: systemSnapshot,
            configuration: configuration,
            rotationIndex: rotationIndex
        )
    }

    func refresh() async {
        await refreshSystemMetrics(forceDiskRefresh: true)
        let overviewResult = await refreshOverview()
        let realtimeResult = await refreshRealtime()
        ensurePolling(
            overviewResult: overviewResult,
            realtimeResult: realtimeResult
        )
    }

    /// Shared quota refresh path used by both the manual button and five-minute polling.
    func refreshQuota() async {
        guard let quotaRefreshSource, hasStoredCredential else {
            quotaRefreshState = .failed("请先连接 CPA Usage Keeper")
            return
        }
        guard quotaRefreshOperationID == nil else { return }

        // Claim the shared UI state before the first suspension point so the two buttons
        // cannot race each other. The network actor also performs the authoritative check.
        let operationID = UUID()
        let configurationGeneration = quotaConfigurationGeneration
        quotaRefreshOperationID = operationID
        quotaRefreshState = .refreshing
        await synchronizeQuotaRefreshCooldown()
        guard quotaRefreshOperationID == operationID else { return }
        guard quotaRefreshCooldownRemainingSeconds == 0 else {
            quotaRefreshState = .failed(
                "额度更新每分钟最多一次，请在 \(quotaRefreshCooldownRemainingSeconds) 秒后重试"
            )
            quotaRefreshOperationID = nil
            return
        }

        do {
            let result = try await quotaRefreshSource.refreshHighestPriorityCodexQuota()
            if quotaConfigurationGeneration == configurationGeneration {
                let weeklyWindow = result.quota.weeklyPrimaryWindow
                quotaRemainingPercent = weeklyWindow?.remainingPercent
                quotaLastUpdatedAt = result.refreshedAt
                quotaResetAt = weeklyWindow?.resetDate
                    ?? weeklyWindow?.resetAfterSeconds.map {
                        result.refreshedAt.addingTimeInterval(TimeInterval($0))
                    }
                quotaRefreshState = .succeeded(result.refreshedAt)
            }
        } catch is CancellationError {
            if quotaConfigurationGeneration == configurationGeneration {
                quotaRefreshState = .failed("额度更新已取消；已发出的请求不会自动重试")
            }
        } catch {
            if quotaConfigurationGeneration == configurationGeneration {
                quotaRefreshState = .failed(error.localizedDescription)
            }
        }
        guard quotaRefreshOperationID == operationID else { return }
        quotaRefreshOperationID = nil
        if quotaConfigurationGeneration != configurationGeneration {
            quotaRefreshState = hasStoredCredential ? .idle : .failed("请先连接 CPA Usage Keeper")
        }
        await synchronizeQuotaRefreshCooldown()
    }

    func resetDailyUsageCounter() {
        rebaseDailyUsageCounter(using: rawSnapshot, at: Date())
        usageAlertManager.resetDailyBudgetAlert()
        Task { await evaluateUsageAlerts() }
    }

    var canRefreshQuota: Bool {
        hasConfiguredSource
            && hasStoredCredential
            && quotaRefreshCooldownRemainingSeconds == 0
            && quotaRefreshOperationID == nil
    }

    var quotaRefreshButtonLabel: String {
        if quotaRefreshState == .refreshing { return "更新中" }
        if quotaRefreshCooldownRemainingSeconds > 0 {
            return "\(quotaRefreshCooldownRemainingSeconds)s 后可更新"
        }
        return "更新额度"
    }

    var quotaRefreshStatusDetail: String {
        switch quotaRefreshState {
        case .idle:
            quotaRefreshCooldownRemainingSeconds > 0
                ? "额度更新已进入 1 分钟冷却"
                : "手动更新优先级最高的 Codex 凭证，每分钟最多一次"
        case .refreshing:
            "正在更新优先级最高的 Codex 凭证额度"
        case let .succeeded(date):
            "额度已更新 · \(date.formatted(date: .omitted, time: .standard))"
        case let .failed(message):
            message
        }
    }

    var quotaRemainingPercentText: String {
        guard let quotaRemainingPercent else { return "额度暂无数据" }
        return "Weekly 剩余 \(Int(quotaRemainingPercent.rounded()))%"
    }

    var quotaLastUpdatedText: String {
        guard let quotaLastUpdatedAt else { return "尚未更新" }
        return "最后更新 \(quotaLastUpdatedAt.formatted(date: .omitted, time: .shortened))"
    }

    var quotaResetDateText: String {
        guard let quotaResetAt else { return "未知" }
        let components = Calendar.current.dateComponents(
            [.month, .day, .hour, .minute],
            from: quotaResetAt
        )
        guard
            let month = components.month,
            let day = components.day,
            let hour = components.hour,
            let minute = components.minute
        else {
            return "未知"
        }
        return String(format: "%02d/%02d %02d:%02d", month, day, hour, minute)
    }

    var quotaResetRelativeText: String {
        guard let quotaResetAt else { return "" }
        let remainingSeconds = max(0, Int(quotaResetAt.timeIntervalSinceNow.rounded()))
        if remainingSeconds == 0 { return "即将重置" }

        let days = remainingSeconds / 86_400
        let hours = (remainingSeconds % 86_400) / 3_600
        let minutes = (remainingSeconds % 3_600) / 60
        if days > 0 { return "约 \(days) 天 \(hours) 小时后" }
        if hours > 0 { return "约 \(hours) 小时 \(minutes) 分钟后" }
        return "约 \(max(minutes, 1)) 分钟后"
    }

    func requestNotificationPermission() async -> NotificationPermissionState {
        let state = await usageAlertManager.requestPermission()
        notificationPermissionState = state
        if state.canDeliver {
            await evaluateUsageAlerts()
        }
        return state
    }

    func refreshNotificationPermissionState() async {
        notificationPermissionState = await usageAlertManager.permissionState()
    }

    func configureSource(baseURLString: String, password: String) async -> Bool {
        var nextConfiguration = sourceConfiguration
        nextConfiguration.baseURLString = baseURLString

        do {
            _ = try nextConfiguration.validatedBaseURL()
            if !password.isEmpty {
                nextConfiguration.password = password
            }
            guard !nextConfiguration.password.isEmpty else {
                throw SourceConfigurationError.missingPassword
            }

            cancelSourcePolling()
            if let source {
                try source.configure(nextConfiguration)
            } else {
                source = try CPAUsageKeeperSource(configuration: nextConfiguration)
            }
            if let quotaRefreshSource {
                try quotaRefreshSource.configure(nextConfiguration)
            } else {
                quotaRefreshSource = try CPAQuotaRefreshSource(configuration: nextConfiguration)
            }
            sourceConfiguration = nextConfiguration
            sourceConfigurationStore.save(nextConfiguration)
            hasStoredCredential = true
            quotaConfigurationGeneration += 1
            quotaRefreshCooldownTask?.cancel()
            quotaRefreshCooldownTask = nil
            if quotaRefreshOperationID == nil {
                quotaRefreshState = .idle
            }
            await synchronizeQuotaRefreshCooldown()

            let overviewResult = await refreshOverview()
            let realtimeResult = overviewResult == .succeeded
                ? await refreshRealtime()
                : .skipped
            ensurePolling(
                overviewResult: overviewResult,
                realtimeResult: realtimeResult
            )
            if overviewResult == .succeeded {
                scheduleQuotaPolling(performImmediately: true)
            }
            return overviewResult == .succeeded
        } catch {
            sourceConnectionState = .failed(error.localizedDescription)
            refreshState = .failed(error.localizedDescription)
            return false
        }
    }

    func clearSourceCredential() {
        cancelSourcePolling()
        hasConnectedSuccessfully = false

        var nextConfiguration = sourceConfiguration
        nextConfiguration.password = ""
        do {
            try source?.configure(nextConfiguration)
            try quotaRefreshSource?.configure(nextConfiguration)
            sourceConfiguration = nextConfiguration
            sourceConfigurationStore.save(nextConfiguration)
            hasStoredCredential = false
            quotaConfigurationGeneration += 1
            quotaRefreshCooldownTask?.cancel()
            quotaRefreshCooldownTask = nil
            sourceConnectionState = .needsCredential
            refreshState = .idle
            if quotaRefreshOperationID == nil {
                quotaRefreshState = .idle
            }
        } catch {
            sourceConnectionState = .failed(error.localizedDescription)
        }
    }

    var connectionStatusText: String {
        switch sourceConnectionState {
        case .needsCredential: "等待配置"
        case .connecting: "正在连接"
        case .reconnecting: "正在重连"
        case .connected: "已连接"
        case .failed: "连接失败"
        }
    }

    var connectionStatusDetail: String {
        switch sourceConnectionState {
        case .needsCredential:
            if !hasConfiguredSource {
                "填写服务地址和密码后开始读取数据"
            } else {
                "输入密码后开始读取数据"
            }
        case .connecting:
            "正在登录并获取用量"
        case let .reconnecting(message):
            "\(message)；将自动重试"
        case let .connected(date):
            "上次更新 \(date.formatted(date: .omitted, time: .standard))"
        case let .failed(message):
            message
        }
    }

    var isSourceConnected: Bool {
        if case .connected = sourceConnectionState { return true }
        return false
    }

    var hasConfiguredSource: Bool {
        source != nil
    }

    private func prepareSource() async {
        hasStoredCredential = !sourceConfiguration.password.isEmpty
        await synchronizeQuotaRefreshCooldown()
        guard source != nil, hasStoredCredential else {
            sourceConnectionState = .needsCredential
            return
        }

        scheduleQuotaPolling(performImmediately: true)
        let overviewResult = await refreshOverview()
        let realtimeResult = overviewResult == .succeeded
            ? await refreshRealtime()
            : .skipped
        ensurePolling(
            overviewResult: overviewResult,
            realtimeResult: realtimeResult
        )
    }

    private func refreshOverview() async -> SourceRefreshResult {
        guard let source else {
            refreshState = .idle
            sourceConnectionState = .needsCredential
            return .skipped
        }
        guard !isOverviewRefreshing else { return .skipped }
        isOverviewRefreshing = true
        defer { isOverviewRefreshing = false }
        refreshState = .refreshing
        if !hasConnectedSuccessfully {
            sourceConnectionState = .connecting
        }

        do {
            applyRawSnapshot(rawSnapshot.applying(try await source.fetchOverview()))
            hasConnectedSuccessfully = true
            refreshState = .idle
            sourceConnectionState = .connected(snapshot.updatedAt)
            await evaluateUsageAlerts()
            return .succeeded
        } catch {
            let message = error.localizedDescription
            refreshState = .failed(message)

            if isRetryable(error) {
                sourceConnectionState = .reconnecting(message)
                return .retryableFailure
            }

            sourceConnectionState = .failed(message)
            return .terminalFailure
        }
    }

    private func refreshRealtime() async -> SourceRefreshResult {
        guard let source else { return .skipped }
        guard !isRealtimeRefreshing else { return .skipped }
        isRealtimeRefreshing = true
        defer { isRealtimeRefreshing = false }
        refreshState = .refreshing

        do {
            applyRawSnapshot(rawSnapshot.applying(try await source.fetchRealtime()))
            hasConnectedSuccessfully = true
            refreshState = .idle
            sourceConnectionState = .connected(snapshot.updatedAt)
            await evaluateUsageAlerts()
            return .succeeded
        } catch {
            let message = error.localizedDescription
            refreshState = .failed(message)
            if isRetryable(error) {
                sourceConnectionState = .reconnecting(message)
                return .retryableFailure
            }
            sourceConnectionState = .failed(message)
            return .terminalFailure
        }
    }

    private func ensurePolling(
        overviewResult: SourceRefreshResult,
        realtimeResult: SourceRefreshResult
    ) {
        if overviewResult.shouldContinuePolling, overviewPollingTask == nil {
            scheduleOverviewPolling()
        }
        if realtimeResult.shouldContinuePolling, realtimePollingTask == nil {
            scheduleRealtimePolling()
        }
    }

    private func cancelSourcePolling() {
        overviewPollingTask?.cancel()
        realtimePollingTask?.cancel()
        quotaPollingTask?.cancel()
        overviewPollingTask = nil
        realtimePollingTask = nil
        quotaPollingTask = nil
    }

    private func scheduleQuotaPolling(performImmediately: Bool) {
        quotaPollingTask?.cancel()
        let interval = Self.quotaRefreshIntervalSeconds
        let generation = quotaConfigurationGeneration

        quotaPollingTask = Task { [weak self] in
            if performImmediately {
                await self?.refreshQuotaAutomatically(configurationGeneration: generation)
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await self.refreshQuotaAutomatically(configurationGeneration: generation)
            }
        }
    }

    private func refreshQuotaAutomatically(configurationGeneration: Int) async {
        guard
            configurationGeneration == quotaConfigurationGeneration,
            hasConfiguredSource,
            hasStoredCredential
        else {
            return
        }

        await synchronizeQuotaRefreshCooldown()
        let cooldown = quotaRefreshCooldownRemainingSeconds
        if cooldown > 0 {
            do {
                try await Task.sleep(for: .seconds(cooldown))
            } catch {
                return
            }
        }

        guard
            !Task.isCancelled,
            configurationGeneration == quotaConfigurationGeneration
        else {
            return
        }
        await refreshQuota()
    }

    private func scheduleOverviewPolling() {
        overviewPollingTask?.cancel()
        let interval = overviewRefreshIntervalSeconds

        overviewPollingTask = Task { [weak self] in
            var nextDelay = interval

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(nextDelay))
                } catch {
                    return
                }

                guard let self, !Task.isCancelled else { return }

                switch await self.refreshOverview() {
                case .succeeded, .skipped:
                    nextDelay = interval
                case .retryableFailure:
                    nextDelay = min(max(nextDelay * 2, interval), 300)
                case .terminalFailure:
                    self.overviewPollingTask = nil
                    return
                }
            }
        }
    }

    private func scheduleRealtimePolling() {
        realtimePollingTask?.cancel()
        let interval = realtimeRefreshIntervalSeconds

        realtimePollingTask = Task { [weak self] in
            var nextDelay = interval

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(nextDelay))
                } catch {
                    return
                }

                guard let self, !Task.isCancelled else { return }

                switch await self.refreshRealtime() {
                case .succeeded, .skipped:
                    nextDelay = interval
                case .retryableFailure:
                    nextDelay = min(max(nextDelay * 2, interval), 60)
                case .terminalFailure:
                    self.realtimePollingTask = nil
                    return
                }
            }
        }
    }

    private func scheduleSystemMetricsPolling() {
        systemMetricsTask?.cancel()
        systemMetricsTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshSystemMetrics()
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            await self.refreshSystemMetrics()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refreshSystemMetrics()
            }
        }
    }

    private func refreshSystemMetrics(forceDiskRefresh: Bool = false) async {
        systemSnapshot = await systemMetricsMonitor.sample(forceDiskRefresh: forceDiskRefresh)
    }

    private func applyRawSnapshot(_ nextRawSnapshot: MetricSnapshot) {
        rawSnapshot = nextRawSnapshot

        let today = DailyUsageCounter.dayIdentifier()
        if let reset = dailyUsageCounterReset, reset.dayIdentifier != today {
            dailyUsageCounterReset = nil
            dailyUsageCounterResetStore.clear()
        } else if let reset = dailyUsageCounterReset,
                  let rebasedReset = DailyUsageCounter.automaticallyRebasedReset(
                      rawSnapshot: nextRawSnapshot,
                      reset: reset,
                      at: Date()
                  ) {
            dailyUsageCounterReset = rebasedReset
            dailyUsageCounterResetStore.save(rebasedReset)
        }

        snapshot = dailyUsageCounterReset.map {
            DailyUsageCounter.adjustedSnapshot(nextRawSnapshot, using: $0)
        } ?? nextRawSnapshot
    }

    private func rebaseDailyUsageCounter(using rawSnapshot: MetricSnapshot, at date: Date) {
        let reset = DailyUsageCounter.reset(for: rawSnapshot, at: date)
        dailyUsageCounterReset = reset
        dailyUsageCounterResetStore.save(reset)
        snapshot = DailyUsageCounter.adjustedSnapshot(rawSnapshot, using: reset, at: date)
    }

    private func synchronizeQuotaRefreshCooldown() async {
        guard let quotaRefreshSource else {
            quotaRefreshCooldownRemainingSeconds = 0
            quotaRefreshCooldownTask?.cancel()
            quotaRefreshCooldownTask = nil
            return
        }

        let generation = quotaConfigurationGeneration
        let remaining = await quotaRefreshSource.cooldownRemainingSeconds()
        guard generation == quotaConfigurationGeneration else { return }
        quotaRefreshCooldownRemainingSeconds = remaining
        guard quotaRefreshCooldownRemainingSeconds > 0 else {
            quotaRefreshCooldownTask?.cancel()
            quotaRefreshCooldownTask = nil
            return
        }
        scheduleQuotaRefreshCooldownCountdownIfNeeded()
    }

    private func scheduleQuotaRefreshCooldownCountdownIfNeeded() {
        guard quotaRefreshCooldownTask == nil else { return }
        let generation = quotaConfigurationGeneration
        quotaRefreshCooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, let source = self.quotaRefreshSource, !Task.isCancelled else {
                    return
                }
                let remaining = await source.cooldownRemainingSeconds()
                guard
                    !Task.isCancelled,
                    self.quotaConfigurationGeneration == generation
                else {
                    return
                }
                self.quotaRefreshCooldownRemainingSeconds = remaining
                if remaining == 0 {
                    self.quotaRefreshCooldownTask = nil
                    return
                }
            }
        }
    }

    private func scheduleRotation() {
        rotationTask?.cancel()
        rotationTask = nil

        let enabledCount = configuration.fields.filter(\.isEnabled).count
        guard configuration.displayMode == .rotating, enabledCount > 1 else { return }
        let interval = [5, 10, 15].contains(configuration.rotationIntervalSeconds)
            ? configuration.rotationIntervalSeconds
            : 5

        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                let currentCount = self.configuration.fields.filter(\.isEnabled).count
                guard currentCount > 0 else {
                    self.rotationIndex = 0
                    continue
                }
                self.rotationIndex = (self.rotationIndex + 1) % currentCount
            }
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        guard let sourceError = error as? CPAUsageKeeperError else { return false }

        return switch sourceError {
        case .network, .rateLimited, .serverUnavailable:
            true
        case .authenticationRequired,
             .invalidResponse,
             .responseTooLarge,
             .decoding:
            false
        }
    }

    private func evaluateUsageAlerts() async {
        await usageAlertManager.evaluate(
            snapshot: snapshot,
            configuration: alertConfiguration
        )
    }

    func setEnabled(_ isEnabled: Bool, for kind: MetricKind) {
        mutateField(kind) { $0.isEnabled = isEnabled }
    }

    func setLabel(_ label: String, for kind: MetricKind) {
        mutateField(kind) { $0.label = label }
    }

    func moveField(_ kind: MetricKind, direction: Int) {
        guard let index = configuration.fields.firstIndex(where: { $0.kind == kind }) else { return }
        let destination = index + direction
        guard configuration.fields.indices.contains(destination) else { return }
        configuration.fields.swapAt(index, destination)
    }

    func canMove(_ kind: MetricKind, direction: Int) -> Bool {
        guard let index = configuration.fields.firstIndex(where: { $0.kind == kind }) else { return false }
        return configuration.fields.indices.contains(index + direction)
    }

    func resetConfiguration() {
        configuration = .default
    }

    private func mutateField(
        _ kind: MetricKind,
        mutation: (inout DisplayFieldConfiguration) -> Void
    ) {
        guard let index = configuration.fields.firstIndex(where: { $0.kind == kind }) else { return }
        mutation(&configuration.fields[index])
    }
}

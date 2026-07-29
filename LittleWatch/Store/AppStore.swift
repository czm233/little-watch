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
    @Published private(set) var systemSnapshot: SystemMetricsSnapshot = .empty
    @Published private(set) var refreshState: RefreshState = .idle
    @Published private(set) var sourceConnectionState: SourceConnectionState = .needsCredential
    @Published private(set) var hasStoredCredential = false
    @Published private(set) var sourceConfiguration: SourceConfiguration

    let sourceName = "CPA Usage Keeper"

    private var source: CPAUsageKeeperSource?
    private let configurationStore: ConfigurationStore
    private let sourceConfigurationStore: SourceConfigurationStore
    private let credentialStore: KeychainCredentialStore
    private let formatter = MenuBarFormatter()
    private let systemMetricsMonitor = SystemMetricsMonitor()
    private var pollingTask: Task<Void, Never>?
    private var systemMetricsTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var rotationIndex = 0
    private var hasConnectedSuccessfully = false

    init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        sourceConfigurationStore: SourceConfigurationStore = SourceConfigurationStore(),
        credentialStore: KeychainCredentialStore = KeychainCredentialStore()
    ) {
        let loadedSourceConfiguration = sourceConfigurationStore.load()
        let resolvedSourceConfiguration = (try? loadedSourceConfiguration.validatedBaseURL()) == nil
            ? SourceConfiguration.default
            : loadedSourceConfiguration

        self.configurationStore = configurationStore
        self.sourceConfigurationStore = sourceConfigurationStore
        self.credentialStore = credentialStore
        self.sourceConfiguration = resolvedSourceConfiguration
        self.configuration = configurationStore.load()
        self.snapshot = MetricSnapshot(
            costUSD: 0,
            tokenCount: 0,
            updatedAt: Date()
        )
        self.source = try? CPAUsageKeeperSource(
            configuration: resolvedSourceConfiguration,
            credentialStore: credentialStore
        )

        Task { [weak self] in
            await self?.prepareSource()
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
        await refreshSystemMetrics()
        let result = await refreshFromSource()
        if result.shouldContinuePolling, pollingTask == nil {
            schedulePolling()
        }
    }

    func configureSource(baseURLString: String, password: String) async -> Bool {
        var nextConfiguration = sourceConfiguration
        nextConfiguration.baseURLString = baseURLString

        do {
            _ = try nextConfiguration.validatedBaseURL()
            if !password.isEmpty {
                try credentialStore.savePassword(password)
            }
            guard try credentialStore.containsPassword() else {
                throw SourceConfigurationError.missingPassword
            }

            pollingTask?.cancel()
            pollingTask = nil
            if let source {
                try source.configure(nextConfiguration)
            } else {
                source = try CPAUsageKeeperSource(
                    configuration: nextConfiguration,
                    credentialStore: credentialStore
                )
            }
            sourceConfiguration = nextConfiguration
            sourceConfigurationStore.save(nextConfiguration)
            hasStoredCredential = true

            let result = await refreshFromSource()
            if result.shouldContinuePolling { schedulePolling() }
            return result == .succeeded
        } catch {
            sourceConnectionState = .failed(error.localizedDescription)
            refreshState = .failed(error.localizedDescription)
            return false
        }
    }

    func clearSourceCredential() {
        pollingTask?.cancel()
        pollingTask = nil
        hasConnectedSuccessfully = false
        do {
            try credentialStore.deletePassword()
            hasStoredCredential = false
            sourceConnectionState = .needsCredential
            refreshState = .idle
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
        do {
            hasStoredCredential = try credentialStore.containsPassword()
            guard source != nil, hasStoredCredential else {
                sourceConnectionState = .needsCredential
                return
            }

            let result = await refreshFromSource()
            if result.shouldContinuePolling {
                schedulePolling()
            }
        } catch {
            sourceConnectionState = .failed(error.localizedDescription)
        }
    }

    private func refreshFromSource() async -> SourceRefreshResult {
        guard let source else {
            refreshState = .idle
            sourceConnectionState = .needsCredential
            return .skipped
        }
        guard refreshState != .refreshing else { return .skipped }
        refreshState = .refreshing
        if !hasConnectedSuccessfully {
            sourceConnectionState = .connecting
        }

        do {
            snapshot = try await source.fetch()
            hasConnectedSuccessfully = true
            refreshState = .idle
            sourceConnectionState = .connected(snapshot.updatedAt)
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

    private func schedulePolling() {
        pollingTask?.cancel()
        let interval = max(sourceConfiguration.pollingIntervalSeconds, 5)

        pollingTask = Task { [weak self] in
            var nextDelay = interval

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(nextDelay))
                } catch {
                    return
                }

                guard let self, !Task.isCancelled else { return }

                switch await self.refreshFromSource() {
                case .succeeded, .skipped:
                    nextDelay = interval
                case .retryableFailure:
                    nextDelay = min(max(nextDelay * 2, interval), 60)
                case .terminalFailure:
                    self.pollingTask = nil
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

    private func refreshSystemMetrics() async {
        systemSnapshot = await systemMetricsMonitor.sample()
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
        case .authenticationRequired, .invalidResponse, .responseTooLarge, .decoding:
            false
        }
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

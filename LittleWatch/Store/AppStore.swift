import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var configuration: AppConfiguration {
        didSet {
            configurationStore.save(configuration)
            rotationIndex = 0
            scheduleRotation()
        }
    }
    @Published private(set) var systemSnapshot: SystemMetricsSnapshot = .empty

    private let configurationStore: ConfigurationStore
    private let formatter = MenuBarFormatter()
    private let systemMetricsMonitor = SystemMetricsMonitor()
    private var systemMetricsTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var rotationIndex = 0

    init(configurationStore: ConfigurationStore = ConfigurationStore()) {
        self.configurationStore = configurationStore
        self.configuration = configurationStore.load()

        scheduleSystemMetricsPolling()
        scheduleRotation()
    }

    var menuBarTitle: String {
        formatter.title(
            for: systemSnapshot,
            configuration: configuration,
            rotationIndex: rotationIndex
        )
    }

    func refresh() async {
        await refreshSystemMetrics(forceDiskRefresh: true)
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

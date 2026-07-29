import Foundation

@MainActor
protocol MetricSource {
    var id: String { get }
    var displayName: String { get }
    func fetch() async throws -> MetricSnapshot
}

@MainActor
struct MockMetricSource: MetricSource {
    let id = "mock.usage"
    let displayName = "Mock Source"

    func fetch() async throws -> MetricSnapshot {
        try await Task.sleep(for: .milliseconds(280))
        return MetricSnapshot(
            costUSD: 12.84,
            tokenCount: 184_240,
            updatedAt: Date()
        )
    }
}

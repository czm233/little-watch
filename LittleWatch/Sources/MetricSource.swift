import Foundation

@MainActor
protocol MetricSource {
    var id: String { get }
    var displayName: String { get }
    func fetchOverview() async throws -> MetricOverviewSnapshot
    func fetchRealtime() async throws -> MetricRealtimeSnapshot
}

@MainActor
struct MockMetricSource: MetricSource {
    let id = "mock.usage"
    let displayName = "Mock Source"

    func fetchOverview() async throws -> MetricOverviewSnapshot {
        try await Task.sleep(for: .milliseconds(280))
        return MetricOverviewSnapshot(
            costUSD: 12.84,
            tokenCount: 184_240,
            updatedAt: Date(),
            totalRequests: 126,
            fallbackTokensPerMinute: 840,
            fallbackRequestsPerMinute: 3,
            projectedEndOfDayCostUSD: 18.2
        )
    }

    func fetchRealtime() async throws -> MetricRealtimeSnapshot {
        try await Task.sleep(for: .milliseconds(120))
        let now = Date()
        let tpm = [620.0, 740, 840].enumerated().map { index, value in
            UsageRatePoint(timestamp: now.addingTimeInterval(Double(index - 2) * 120), value: value)
        }
        let rpm = [2.0, 2.5, 3].enumerated().map { index, value in
            UsageRatePoint(timestamp: now.addingTimeInterval(Double(index - 2) * 120), value: value)
        }
        return MetricRealtimeSnapshot(
            updatedAt: now,
            tokensPerMinuteTrend: tpm,
            requestsPerMinuteTrend: rpm,
            usageSpike: nil
        )
    }
}

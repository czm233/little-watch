import Foundation

struct SystemMetricsSnapshot: Equatable, Sendable {
    let cpuUsagePercent: Double
    let memoryUsagePercent: Double
    let diskUsagePercent: Double
    let diskFreeBytes: Int64
    let updatedAt: Date

    static let empty = SystemMetricsSnapshot(
        cpuUsagePercent: 0,
        memoryUsagePercent: 0,
        diskUsagePercent: 0,
        diskFreeBytes: 0,
        updatedAt: .distantPast
    )
}

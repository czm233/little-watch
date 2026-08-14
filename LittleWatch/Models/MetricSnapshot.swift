import Foundation

enum UsageRateMetric: String, Equatable, Sendable {
    case tokensPerMinute
    case requestsPerMinute
}

struct UsageRatePoint: Equatable, Sendable, Identifiable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

struct UsageSpikeEvent: Equatable, Sendable {
    let metric: UsageRateMetric
    let currentValue: Double
    let baselineAverage: Double
    let multiple: Double
    let detectedAt: Date
}

struct MetricOverviewSnapshot: Equatable, Sendable {
    let costUSD: Double
    let costAvailable: Bool
    let tokenCount: Int
    let tokenCountAvailable: Bool
    let updatedAt: Date
    let totalRequests: Int?
    let fallbackTokensPerMinute: Double?
    let fallbackRequestsPerMinute: Double?
    let projectedEndOfDayCostUSD: Double?

    init(
        costUSD: Double,
        costAvailable: Bool = true,
        tokenCount: Int,
        tokenCountAvailable: Bool = true,
        updatedAt: Date,
        totalRequests: Int?,
        fallbackTokensPerMinute: Double?,
        fallbackRequestsPerMinute: Double?,
        projectedEndOfDayCostUSD: Double?
    ) {
        self.costUSD = costUSD
        self.costAvailable = costAvailable
        self.tokenCount = tokenCount
        self.tokenCountAvailable = tokenCountAvailable
        self.updatedAt = updatedAt
        self.totalRequests = totalRequests
        self.fallbackTokensPerMinute = fallbackTokensPerMinute
        self.fallbackRequestsPerMinute = fallbackRequestsPerMinute
        self.projectedEndOfDayCostUSD = projectedEndOfDayCostUSD
    }
}

struct MetricRealtimeSnapshot: Equatable, Sendable {
    let updatedAt: Date
    let tokensPerMinuteTrend: [UsageRatePoint]
    let requestsPerMinuteTrend: [UsageRatePoint]
    let usageSpike: UsageSpikeEvent?

    var tokensPerMinute: Double? { tokensPerMinuteTrend.last?.value }
    var requestsPerMinute: Double? { requestsPerMinuteTrend.last?.value }
}

struct MetricSnapshot: Equatable, Sendable {
    let costUSD: Double
    let costAvailable: Bool
    let tokenCount: Int
    let tokenCountAvailable: Bool
    let updatedAt: Date
    let totalRequests: Int?
    let tokensPerMinute: Double?
    let requestsPerMinute: Double?
    let projectedEndOfDayCostUSD: Double?
    let tokensPerMinuteTrend: [UsageRatePoint]
    let requestsPerMinuteTrend: [UsageRatePoint]
    let usageSpike: UsageSpikeEvent?

    init(
        costUSD: Double,
        costAvailable: Bool = true,
        tokenCount: Int,
        tokenCountAvailable: Bool = true,
        updatedAt: Date,
        totalRequests: Int? = nil,
        tokensPerMinute: Double? = nil,
        requestsPerMinute: Double? = nil,
        projectedEndOfDayCostUSD: Double? = nil,
        tokensPerMinuteTrend: [UsageRatePoint] = [],
        requestsPerMinuteTrend: [UsageRatePoint] = [],
        usageSpike: UsageSpikeEvent? = nil
    ) {
        self.costUSD = costUSD
        self.costAvailable = costAvailable
        self.tokenCount = tokenCount
        self.tokenCountAvailable = tokenCountAvailable
        self.updatedAt = updatedAt
        self.totalRequests = totalRequests
        self.tokensPerMinute = tokensPerMinute
        self.requestsPerMinute = requestsPerMinute
        self.projectedEndOfDayCostUSD = projectedEndOfDayCostUSD
        self.tokensPerMinuteTrend = tokensPerMinuteTrend
        self.requestsPerMinuteTrend = requestsPerMinuteTrend
        self.usageSpike = usageSpike
    }

    func applying(_ overview: MetricOverviewSnapshot) -> MetricSnapshot {
        MetricSnapshot(
            costUSD: overview.costUSD,
            costAvailable: overview.costAvailable,
            tokenCount: overview.tokenCount,
            tokenCountAvailable: overview.tokenCountAvailable,
            updatedAt: overview.updatedAt,
            totalRequests: overview.totalRequests,
            tokensPerMinute: tokensPerMinute ?? overview.fallbackTokensPerMinute,
            requestsPerMinute: requestsPerMinute ?? overview.fallbackRequestsPerMinute,
            projectedEndOfDayCostUSD: overview.projectedEndOfDayCostUSD,
            tokensPerMinuteTrend: tokensPerMinuteTrend,
            requestsPerMinuteTrend: requestsPerMinuteTrend,
            usageSpike: usageSpike
        )
    }

    func applying(_ realtime: MetricRealtimeSnapshot) -> MetricSnapshot {
        MetricSnapshot(
            costUSD: costUSD,
            costAvailable: costAvailable,
            tokenCount: tokenCount,
            tokenCountAvailable: tokenCountAvailable,
            updatedAt: max(updatedAt, realtime.updatedAt),
            totalRequests: totalRequests,
            tokensPerMinute: realtime.tokensPerMinute,
            requestsPerMinute: realtime.requestsPerMinute,
            projectedEndOfDayCostUSD: projectedEndOfDayCostUSD,
            tokensPerMinuteTrend: realtime.tokensPerMinuteTrend,
            requestsPerMinuteTrend: realtime.requestsPerMinuteTrend,
            usageSpike: realtime.usageSpike
        )
    }
}

struct DailyUsageCounterReset: Codable, Equatable, Sendable {
    let dayIdentifier: String
    let costUSD: Double
    let tokenCount: Int
    let totalRequests: Int?
    let resetAt: Date
}

enum DailyUsageCounter {
    static func dayIdentifier(
        for date: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func reset(
        for rawSnapshot: MetricSnapshot,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyUsageCounterReset {
        DailyUsageCounterReset(
            dayIdentifier: dayIdentifier(for: date, calendar: calendar),
            costUSD: max(rawSnapshot.costUSD, 0),
            tokenCount: max(rawSnapshot.tokenCount, 0),
            totalRequests: rawSnapshot.totalRequests.map { max($0, 0) },
            resetAt: date
        )
    }

    static func adjustedSnapshot(
        _ rawSnapshot: MetricSnapshot,
        using reset: DailyUsageCounterReset,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> MetricSnapshot {
        guard reset.dayIdentifier == dayIdentifier(for: date, calendar: calendar) else {
            return rawSnapshot
        }

        let adjustedCost = max(rawSnapshot.costUSD - reset.costUSD, 0)
        let adjustedTokens = max(rawSnapshot.tokenCount - reset.tokenCount, 0)
        let adjustedRequests: Int? = if let totalRequests = rawSnapshot.totalRequests,
                                        let baselineRequests = reset.totalRequests {
            max(totalRequests - baselineRequests, 0)
        } else {
            rawSnapshot.totalRequests
        }

        return MetricSnapshot(
            costUSD: adjustedCost,
            costAvailable: rawSnapshot.costAvailable,
            tokenCount: adjustedTokens,
            tokenCountAvailable: rawSnapshot.tokenCountAvailable,
            updatedAt: rawSnapshot.updatedAt,
            totalRequests: adjustedRequests,
            tokensPerMinute: rawSnapshot.tokensPerMinute,
            requestsPerMinute: rawSnapshot.requestsPerMinute,
            projectedEndOfDayCostUSD: projectedCost(
                currentCost: adjustedCost,
                resetAt: reset.resetAt,
                now: date,
                calendar: calendar
            ),
            tokensPerMinuteTrend: rawSnapshot.tokensPerMinuteTrend,
            requestsPerMinuteTrend: rawSnapshot.requestsPerMinuteTrend,
            usageSpike: rawSnapshot.usageSpike
        )
    }

    static func automaticallyRebasedReset(
        rawSnapshot: MetricSnapshot,
        reset: DailyUsageCounterReset,
        at date: Date = Date()
    ) -> DailyUsageCounterReset? {
        var costUSD = reset.costUSD
        var tokenCount = reset.tokenCount
        var totalRequests = reset.totalRequests
        var didRebase = false

        // These counters are refreshed independently by the service. Rebase
        // only the metric that moved backwards so a delayed metric cannot pin
        // another counter at zero.
        if rawSnapshot.costAvailable,
           rawSnapshot.costUSD.isFinite,
           rawSnapshot.costUSD + 0.000_001 < costUSD {
            costUSD = max(rawSnapshot.costUSD, 0)
            didRebase = true
        }

        if rawSnapshot.tokenCountAvailable,
           rawSnapshot.tokenCount < tokenCount {
            tokenCount = max(rawSnapshot.tokenCount, 0)
            didRebase = true
        }

        if let rawRequests = rawSnapshot.totalRequests,
           let baselineRequests = totalRequests,
           rawRequests < baselineRequests {
            totalRequests = max(rawRequests, 0)
            didRebase = true
        }

        guard didRebase else { return nil }
        return DailyUsageCounterReset(
            dayIdentifier: reset.dayIdentifier,
            costUSD: costUSD,
            tokenCount: tokenCount,
            totalRequests: totalRequests,
            resetAt: date
        )
    }

    static func shouldAutomaticallyRebase(
        rawSnapshot: MetricSnapshot,
        reset: DailyUsageCounterReset
    ) -> Bool {
        automaticallyRebasedReset(rawSnapshot: rawSnapshot, reset: reset) != nil
    }

    private static func projectedCost(
        currentCost: Double,
        resetAt: Date,
        now: Date,
        calendar: Calendar
    ) -> Double? {
        guard
            currentCost.isFinite,
            currentCost >= 0,
            resetAt <= now,
            calendar.isDate(resetAt, inSameDayAs: now),
            let startOfNextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: now)
            )
        else {
            return nil
        }

        let elapsed = now.timeIntervalSince(resetAt)
        let remaining = startOfNextDay.timeIntervalSince(now)
        guard elapsed > 0, remaining >= 0 else { return nil }
        return currentCost * (elapsed + remaining) / elapsed
    }
}

enum UsageAnalytics {
    static func projectedEndOfDayCost(
        currentCost: Double,
        at date: Date,
        timeZoneIdentifier: String?
    ) -> Double? {
        guard currentCost.isFinite, currentCost >= 0 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = .current
        }

        let startOfDay = calendar.startOfDay(for: date)
        guard
            let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        else {
            return nil
        }

        let elapsed = date.timeIntervalSince(startOfDay)
        let dayDuration = startOfNextDay.timeIntervalSince(startOfDay)
        guard elapsed > 0, dayDuration > 0 else { return nil }
        return currentCost * dayDuration / elapsed
    }

    static func detectSpike(
        tokensPerMinute: [UsageRatePoint],
        requestsPerMinute: [UsageRatePoint]
    ) -> UsageSpikeEvent? {
        let candidates = [
            spike(
                in: tokensPerMinute,
                metric: .tokensPerMinute,
                minimumCurrentValue: 100
            ),
            spike(
                in: requestsPerMinute,
                metric: .requestsPerMinute,
                minimumCurrentValue: 2
            )
        ].compactMap { $0 }

        return candidates.max { first, second in
            if first.multiple == second.multiple {
                return first.detectedAt < second.detectedAt
            }
            return first.multiple < second.multiple
        }
    }

    private static func spike(
        in points: [UsageRatePoint],
        metric: UsageRateMetric,
        minimumCurrentValue: Double
    ) -> UsageSpikeEvent? {
        let ordered = points
            .filter { $0.value.isFinite && $0.value >= 0 }
            .sorted { $0.timestamp < $1.timestamp }
        guard ordered.count >= 6, let latest = ordered.last else { return nil }

        let baseline = ordered.dropLast().suffix(12).map(\.value)
        guard baseline.count >= 5 else { return nil }
        let baselineAverage = baseline.reduce(0, +) / Double(baseline.count)
        guard
            baselineAverage > 0,
            latest.value >= minimumCurrentValue,
            latest.value >= baselineAverage * 2
        else {
            return nil
        }

        return UsageSpikeEvent(
            metric: metric,
            currentValue: latest.value,
            baselineAverage: baselineAverage,
            multiple: latest.value / baselineAverage,
            detectedAt: latest.timestamp
        )
    }
}

enum RefreshState: Equatable {
    case idle
    case refreshing
    case failed(String)
}

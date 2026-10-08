import XCTest
@testable import LittleWatch

final class MenuBarFormatterTests: XCTestCase {
    private let snapshot = MetricSnapshot(
        costUSD: 12.84,
        tokenCount: 184_240,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
    private let systemSnapshot = SystemMetricsSnapshot(
        cpuUsagePercent: 40.4,
        memoryUsagePercent: 79.6,
        diskUsagePercent: 38.2,
        diskFreeBytes: 20_000_000_000,
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    func testDefaultTitle() {
        let title = MenuBarFormatter().title(
            for: snapshot,
            configuration: .default
        )

        XCTAssertEqual(title, "$12.84 · 184K tok · CPU 0% · MEM 0%")
    }

    func testReorderedLabeledTitle() {
        var configuration = AppConfiguration.default
        configuration.fields.reverse()
        configuration.showLabels = true
        configuration.separator = .pipe

        let title = MenuBarFormatter().title(
            for: snapshot,
            configuration: configuration
        )

        XCTAssertEqual(title, "内存 0% | CPU 0% | Token 184K tok | 消费 $12.84")
    }

    func testFallsBackWhenEverythingIsHidden() {
        var configuration = AppConfiguration.default
        configuration.fields.indices.forEach { configuration.fields[$0].isEnabled = false }

        let title = MenuBarFormatter().title(
            for: snapshot,
            configuration: configuration
        )

        XCTAssertEqual(title, "Little Watch")
    }

    func testConfigurationPersistence() throws {
        let suiteName = "LittleWatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ConfigurationStore(defaults: defaults)
        var configuration = AppConfiguration.default
        configuration.separator = .space
        configuration.compactTokens = false

        store.save(configuration)

        XCTAssertEqual(store.load(), configuration)
    }

    func testFixedCombinationIncludesSelectedSystemMetrics() {
        var configuration = AppConfiguration.default
        configuration.separator = .pipe
        configuration.fields.indices.forEach { configuration.fields[$0].isEnabled = false }
        for kind in [MetricKind.cost, .memory, .diskFree] {
            configuration.fields[configuration.fields.firstIndex(where: { $0.kind == kind })!].isEnabled = true
        }

        let title = MenuBarFormatter().title(
            for: snapshot,
            systemSnapshot: systemSnapshot,
            configuration: configuration
        )

        XCTAssertEqual(title, "$12.84 | MEM 80% | FREE 20.00 GB")
    }

    func testDiskFreeUsesDecimalGigabytes() {
        XCTAssertEqual(
            MenuBarFormatter().formatDiskFree(16_920_000_000),
            "FREE 16.92 GB"
        )
    }

    func testRotatingTitleUsesEnabledFieldOrder() {
        var configuration = AppConfiguration.default
        configuration.displayMode = .rotating
        configuration.fields[configuration.fields.firstIndex(where: { $0.kind == .cpu })!].isEnabled = true

        let formatter = MenuBarFormatter()
        XCTAssertEqual(
            formatter.title(for: snapshot, systemSnapshot: systemSnapshot, configuration: configuration, rotationIndex: 0),
            "$12.84"
        )
        XCTAssertEqual(
            formatter.title(for: snapshot, systemSnapshot: systemSnapshot, configuration: configuration, rotationIndex: 2),
            "CPU 40%"
        )
    }

    func testLegacyConfigurationAddsDisabledSystemFields() throws {
        let suiteName = "LittleWatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            Data(
                """
                {
                  "fields": [
                    {"kind":"cost","isEnabled":true,"label":"金额"},
                    {"kind":"tokens","isEnabled":false,"label":"令牌"}
                  ],
                  "separator":" | ",
                  "showLabels":true,
                  "compactTokens":false,
                  "costPrecision":1
                }
                """.utf8
            ),
            forKey: "littlewatch.display.configuration.v1"
        )

        let configuration = ConfigurationStore(defaults: defaults).load()

        XCTAssertEqual(configuration.fields.map(\.kind), MetricKind.allCases)
        XCTAssertEqual(configuration.fields[0].label, "金额")
        XCTAssertFalse(configuration.fields.dropFirst(2).contains(where: \.isEnabled))
        XCTAssertEqual(configuration.displayMode, .fixed)
        XCTAssertEqual(configuration.rotationIntervalSeconds, 5)
    }
}

final class CPAUsageModelsTests: XCTestCase {
    func testDailyUsageCounterSubtractsSavedResetBaseline() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let resetAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T10:00:00Z"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z"))
        let raw = MetricSnapshot(
            costUSD: 425,
            tokenCount: 650_000,
            updatedAt: now,
            totalRequests: 120
        )
        let reset = DailyUsageCounterReset(
            dayIdentifier: DailyUsageCounter.dayIdentifier(for: resetAt, calendar: calendar),
            costUSD: 400,
            tokenCount: 600_000,
            totalRequests: 100,
            resetAt: resetAt
        )

        let adjusted = DailyUsageCounter.adjustedSnapshot(
            raw,
            using: reset,
            at: now,
            calendar: calendar
        )

        XCTAssertEqual(adjusted.costUSD, 25)
        XCTAssertEqual(adjusted.tokenCount, 50_000)
        XCTAssertEqual(adjusted.totalRequests, 20)
        XCTAssertEqual(try XCTUnwrap(adjusted.projectedEndOfDayCostUSD), 175, accuracy: 0.001)
    }

    func testDailyUsageCounterDoesNotApplyResetFromAnotherDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let resetAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T23:00:00Z"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T01:00:00Z"))
        let raw = MetricSnapshot(costUSD: 25, tokenCount: 50, updatedAt: now)
        let reset = DailyUsageCounter.reset(for: raw, at: resetAt, calendar: calendar)

        let adjusted = DailyUsageCounter.adjustedSnapshot(raw, using: reset, at: now, calendar: calendar)

        XCTAssertEqual(adjusted, raw)
    }

    func testDailyUsageCounterDetectsServiceResetAndCanRebase() throws {
        let resetAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = DailyUsageCounterReset(
            dayIdentifier: DailyUsageCounter.dayIdentifier(for: resetAt),
            costUSD: 400,
            tokenCount: 600_000,
            totalRequests: 100,
            resetAt: resetAt
        )
        let rawAfterServiceReset = MetricSnapshot(
            costUSD: 2,
            tokenCount: 5_000,
            updatedAt: resetAt.addingTimeInterval(300),
            totalRequests: 2
        )

        XCTAssertTrue(
            DailyUsageCounter.shouldAutomaticallyRebase(
                rawSnapshot: rawAfterServiceReset,
                reset: reset
            )
        )
    }

    func testDailyUsageCounterRebasesCostEvenWhenOtherCountersHaveNotResetYet() {
        let resetAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = DailyUsageCounterReset(
            dayIdentifier: DailyUsageCounter.dayIdentifier(for: resetAt),
            costUSD: 400,
            tokenCount: 600_000,
            totalRequests: 100,
            resetAt: resetAt
        )
        let raw = MetricSnapshot(
            costUSD: 2,
            tokenCount: 650_000,
            updatedAt: resetAt.addingTimeInterval(300),
            totalRequests: 120
        )

        let rebased = DailyUsageCounter.automaticallyRebasedReset(
            rawSnapshot: raw,
            reset: reset,
            at: resetAt.addingTimeInterval(300)
        )

        XCTAssertEqual(rebased?.costUSD, 2)
        XCTAssertEqual(rebased?.tokenCount, 600_000)
        XCTAssertEqual(rebased?.totalRequests, 100)
    }

    func testDailyUsageCounterRebasesEachCounterIndependently() {
        let resetAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = DailyUsageCounterReset(
            dayIdentifier: DailyUsageCounter.dayIdentifier(for: resetAt),
            costUSD: 400,
            tokenCount: 600_000,
            totalRequests: 100,
            resetAt: resetAt
        )

        let tokenReset = MetricSnapshot(
            costUSD: 425,
            tokenCount: 5_000,
            updatedAt: resetAt.addingTimeInterval(300),
            totalRequests: 120
        )
        let requestReset = MetricSnapshot(
            costUSD: 425,
            tokenCount: 650_000,
            updatedAt: resetAt.addingTimeInterval(300),
            totalRequests: 2
        )

        let rebasedTokens = DailyUsageCounter.automaticallyRebasedReset(
            rawSnapshot: tokenReset,
            reset: reset,
            at: tokenReset.updatedAt
        )
        let rebasedRequests = DailyUsageCounter.automaticallyRebasedReset(
            rawSnapshot: requestReset,
            reset: reset,
            at: requestReset.updatedAt
        )

        XCTAssertEqual(rebasedTokens?.costUSD, 400)
        XCTAssertEqual(rebasedTokens?.tokenCount, 5_000)
        XCTAssertEqual(rebasedTokens?.totalRequests, 100)
        XCTAssertEqual(rebasedRequests?.costUSD, 400)
        XCTAssertEqual(rebasedRequests?.tokenCount, 600_000)
        XCTAssertEqual(rebasedRequests?.totalRequests, 2)
    }

    func testUnavailableCostDoesNotTriggerAutomaticCostRebase() {
        let resetAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = DailyUsageCounterReset(
            dayIdentifier: DailyUsageCounter.dayIdentifier(for: resetAt),
            costUSD: 400,
            tokenCount: 600_000,
            totalRequests: nil,
            resetAt: resetAt
        )
        let raw = MetricSnapshot(
            costUSD: 0,
            costAvailable: false,
            tokenCount: 650_000,
            updatedAt: resetAt.addingTimeInterval(300)
        )

        XCTAssertNil(
            DailyUsageCounter.automaticallyRebasedReset(
                rawSnapshot: raw,
                reset: reset,
                at: raw.updatedAt
            )
        )
    }

    func testDiskUsageParserMatchesDFOutput() throws {
        let output = """
        Filesystem     1024-blocks      Used Available Capacity Mounted on
        /dev/disk3s1s1   239362496  12012728  19407392    39%   /
        """

        let result = try XCTUnwrap(SystemMetricsMonitor.parseDiskUsage(output: output))

        XCTAssertEqual(result.usagePercent, 39)
        XCTAssertEqual(result.freeBytes, 19_407_392 * 1024)
    }

    func testOverviewDecodesFlexibleNumbers() throws {
        let data = Data(
            """
            {
              "usage": {
                "total_requests": "42",
                "total_tokens": "12500"
              },
              "summary": {
                "total_cost": "1.25",
                "cost_available": true,
                "rpm": 3.5,
                "tpm": "800"
              },
              "timezone": "Asia/Shanghai"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(CPAUsageOverviewResponse.self, from: data)

        XCTAssertEqual(response.usage.totalRequests, 42)
        XCTAssertEqual(response.usage.totalTokens, 12_500)
        XCTAssertEqual(response.summary.totalCost, 1.25)
        XCTAssertEqual(response.summary.tpm, 800)
    }

    func testRealtimeDecodesLatestVelocity() throws {
        let data = Data(
            """
            {
              "window": "60m",
              "bucket_seconds": 120,
              "token_velocity": [
                {"bucket": "2026-07-23T10:00:00Z", "tokens_per_minute": 321.5, "tokens": 643}
              ],
              "request_level": [
                {"bucket": "2026-07-23T10:00:00Z", "requests_per_minute": 2, "requests": 4}
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(CPAUsageRealtimeResponse.self, from: data)

        XCTAssertEqual(response.window, "60m")
        XCTAssertEqual(response.tokenVelocity.last?.tokensPerMinute, 321.5)
        XCTAssertEqual(response.requestLevel.last?.requestsPerMinute, 2)
    }

    func testProjectedEndOfDayCostUsesServiceTimeZone() throws {
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-23T04:00:00Z")
        )

        let projection = UsageAnalytics.projectedEndOfDayCost(
            currentCost: 6,
            at: date,
            timeZoneIdentifier: "Asia/Shanghai"
        )

        XCTAssertEqual(try XCTUnwrap(projection), 12, accuracy: 0.001)
    }

    func testSpikeDetectionUsesAtLeastFiveBaselinePoints() throws {
        let start = Date(timeIntervalSince1970: 0)
        let tpm = [50.0, 55, 45, 50, 50, 150].enumerated().map { index, value in
            UsageRatePoint(
                timestamp: start.addingTimeInterval(Double(index) * 60),
                value: value
            )
        }

        let spike = try XCTUnwrap(
            UsageAnalytics.detectSpike(
                tokensPerMinute: tpm,
                requestsPerMinute: []
            )
        )

        XCTAssertEqual(spike.metric, .tokensPerMinute)
        XCTAssertEqual(spike.currentValue, 150)
        XCTAssertEqual(spike.baselineAverage, 50, accuracy: 0.001)
        XCTAssertEqual(spike.multiple, 3, accuracy: 0.001)
        XCTAssertEqual(spike.detectedAt, tpm.last?.timestamp)
    }

    func testSpikeDetectionIgnoresLowVolumeAndInsufficientBaselines() {
        let start = Date(timeIntervalSince1970: 0)
        let lowVolume = [1.0, 1, 1, 1, 1, 99].enumerated().map { index, value in
            UsageRatePoint(
                timestamp: start.addingTimeInterval(Double(index) * 60),
                value: value
            )
        }
        let insufficient = [10.0, 10, 10, 100].enumerated().map { index, value in
            UsageRatePoint(
                timestamp: start.addingTimeInterval(Double(index) * 60),
                value: value
            )
        }

        XCTAssertNil(
            UsageAnalytics.detectSpike(
                tokensPerMinute: lowVolume,
                requestsPerMinute: []
            )
        )
        XCTAssertNil(
            UsageAnalytics.detectSpike(
                tokensPerMinute: insufficient,
                requestsPerMinute: []
            )
        )
    }

    func testSnapshotMergesOverviewAndRealtimeWithoutDroppingEitherLayer() throws {
        let initial = MetricSnapshot(
            costUSD: 0,
            tokenCount: 0,
            updatedAt: .distantPast
        )
        let overviewDate = Date(timeIntervalSince1970: 100)
        let realtimeDate = Date(timeIntervalSince1970: 200)
        let point = UsageRatePoint(timestamp: realtimeDate, value: 800)
        let withOverview = initial.applying(
            MetricOverviewSnapshot(
                costUSD: 4.2,
                tokenCount: 12_000,
                updatedAt: overviewDate,
                totalRequests: 42,
                fallbackTokensPerMinute: 700,
                fallbackRequestsPerMinute: 3,
                projectedEndOfDayCostUSD: 8.4
            )
        )
        let merged = withOverview.applying(
            MetricRealtimeSnapshot(
                updatedAt: realtimeDate,
                tokensPerMinuteTrend: [point],
                requestsPerMinuteTrend: [],
                usageSpike: nil
            )
        )

        XCTAssertEqual(merged.costUSD, 4.2)
        XCTAssertEqual(merged.tokenCount, 12_000)
        XCTAssertEqual(merged.projectedEndOfDayCostUSD, 8.4)
        XCTAssertEqual(merged.tokensPerMinuteTrend, [point])
        XCTAssertEqual(merged.tokensPerMinute, 800)
        XCTAssertEqual(merged.updatedAt, realtimeDate)
    }

    func testSourceConfigurationAcceptsHTTPRootAndRejectsEmbeddedCredentials() throws {
        var valid = SourceConfiguration.default
        valid.baseURLString = "http://example.invalid"
        XCTAssertEqual(try valid.validatedBaseURL().absoluteString, "http://example.invalid")

        var invalid = valid
        invalid.baseURLString = "http://user@example.invalid"
        XCTAssertThrowsError(try invalid.validatedBaseURL())
    }

    func testDefaultSourceConfigurationIsUnconfigured() {
        let configuration = SourceConfiguration.default

        XCTAssertTrue(configuration.baseURLString.isEmpty)
        XCTAssertTrue(configuration.password.isEmpty)
        XCTAssertThrowsError(try configuration.validatedBaseURL())
    }

    func testSourceConfigurationDecodesLegacyDataWithoutPassword() throws {
        let data = Data(
            #"{"baseURLString":"http://example.invalid","pollingIntervalSeconds":5,"overviewRange":"today","realtimeWindow":"60m"}"#.utf8
        )

        let configuration = try JSONDecoder().decode(SourceConfiguration.self, from: data)

        XCTAssertTrue(configuration.password.isEmpty)
    }

    func testSourceConfigurationPersistsPasswordInLocalConfiguration() throws {
        var configuration = SourceConfiguration.default
        configuration.password = "local-sample"

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(SourceConfiguration.self, from: data)

        XCTAssertEqual(decoded.password, "local-sample")
    }
}

final class UsageAlertEvaluatorTests: XCTestCase {
    func testBudgetAlertIsDeliveredOnlyOncePerDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = MetricSnapshot(
            costUSD: 12,
            tokenCount: 100,
            updatedAt: now
        )
        let configuration = UsageAlertConfiguration(
            dailyBudgetUSD: 10,
            budgetAlertEnabled: true,
            spikeAlertEnabled: false
        )

        let first = UsageAlertEvaluator.pendingDeliveries(
            snapshot: snapshot,
            configuration: configuration,
            state: .empty,
            now: now
        )

        XCTAssertEqual(first.count, 1)
        guard case let .budget(dayIdentifier, _, _) = first[0] else {
            return XCTFail("应生成预算提醒")
        }
        var state = UsageAlertDeliveryState.empty
        UsageAlertEvaluator.record(first[0], in: &state, deliveredAt: now)
        XCTAssertEqual(state.lastBudgetAlertDay, dayIdentifier)

        XCTAssertTrue(
            UsageAlertEvaluator.pendingDeliveries(
                snapshot: snapshot,
                configuration: configuration,
                state: state,
                now: now.addingTimeInterval(60)
            ).isEmpty
        )
    }

    func testSpikeAlertHonorsCooldownAndAge() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = UsageSpikeEvent(
            metric: .tokensPerMinute,
            currentValue: 500,
            baselineAverage: 100,
            multiple: 5,
            detectedAt: now.addingTimeInterval(-60)
        )
        let snapshot = MetricSnapshot(
            costUSD: 1,
            tokenCount: 100,
            updatedAt: now,
            usageSpike: event
        )
        let configuration = UsageAlertConfiguration(
            dailyBudgetUSD: nil,
            budgetAlertEnabled: false,
            spikeAlertEnabled: true
        )

        let pending = UsageAlertEvaluator.pendingDeliveries(
            snapshot: snapshot,
            configuration: configuration,
            state: .empty,
            now: now
        )
        XCTAssertEqual(pending.count, 1)

        var state = UsageAlertDeliveryState.empty
        UsageAlertEvaluator.record(try XCTUnwrap(pending.first), in: &state, deliveredAt: now)
        XCTAssertTrue(
            UsageAlertEvaluator.pendingDeliveries(
                snapshot: snapshot,
                configuration: configuration,
                state: state,
                now: now.addingTimeInterval(60)
            ).isEmpty
        )

        let staleSnapshot = MetricSnapshot(
            costUSD: 1,
            tokenCount: 100,
            updatedAt: now,
            usageSpike: UsageSpikeEvent(
                metric: .requestsPerMinute,
                currentValue: 10,
                baselineAverage: 2,
                multiple: 5,
                detectedAt: now.addingTimeInterval(-UsageAlertEvaluator.maximumSpikeAge - 1)
            )
        )
        XCTAssertTrue(
            UsageAlertEvaluator.pendingDeliveries(
                snapshot: staleSnapshot,
                configuration: configuration,
                state: .empty,
                now: now
            ).isEmpty
        )
    }

    func testAlertConfigurationPersistence() throws {
        let suiteName = "LittleWatchTests.UsageAlerts.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageAlertConfigurationStore(defaults: defaults)
        let configuration = UsageAlertConfiguration(
            dailyBudgetUSD: 25.5,
            budgetAlertEnabled: true,
            spikeAlertEnabled: true
        )

        store.save(configuration)

        XCTAssertEqual(store.load(), configuration)
    }

    @MainActor
    func testAlertManagerPreventsOverlappingDuplicateDeliveries() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = MetricSnapshot(
            costUSD: 12,
            tokenCount: 100,
            updatedAt: now
        )
        let configuration = UsageAlertConfiguration(
            dailyBudgetUSD: 10,
            budgetAlertEnabled: true,
            spikeAlertEnabled: false
        )
        let suiteName = "LittleWatchTests.UsageAlertOverlap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notificationService = SlowUsageNotificationService()
        let manager = UsageAlertManager(
            notificationService: notificationService,
            store: UsageAlertConfigurationStore(defaults: defaults)
        )

        let firstEvaluation = Task {
            await manager.evaluate(
                snapshot: snapshot,
                configuration: configuration,
                now: now
            )
        }
        while notificationService.deliveries.isEmpty {
            await Task.yield()
        }
        let overlappingEvaluation = Task {
            await manager.evaluate(
                snapshot: snapshot,
                configuration: configuration,
                now: now
            )
        }

        await firstEvaluation.value
        await overlappingEvaluation.value
        XCTAssertEqual(notificationService.deliveries.count, 1)
    }
}

@MainActor
private final class SlowUsageNotificationService: UsageNotificationDelivering {
    private(set) var deliveries: [UsageAlertDelivery] = []

    func permissionState() async -> NotificationPermissionState { .authorized }

    func requestPermission() async -> NotificationPermissionState { .authorized }

    func deliver(_ alert: UsageAlertDelivery) async throws {
        deliveries.append(alert)
        try await Task.sleep(for: .milliseconds(50))
    }
}

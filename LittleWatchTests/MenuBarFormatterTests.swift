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

        XCTAssertEqual(title, "$12.84 · 184K tok")
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

        XCTAssertEqual(title, "Token 184K tok | 消费 $12.84")
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

        XCTAssertEqual(title, "$12.84 | MEM 80% | FREE 18.6G")
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

    func testSourceConfigurationAcceptsHTTPRootAndRejectsEmbeddedCredentials() throws {
        let valid = SourceConfiguration.default
        XCTAssertEqual(try valid.validatedBaseURL().absoluteString, "http://xxx.xxx.xxx.xxx:1234")

        var invalid = valid
        invalid.baseURLString = "http://user@example.invalid"
        XCTAssertThrowsError(try invalid.validatedBaseURL())
    }
}

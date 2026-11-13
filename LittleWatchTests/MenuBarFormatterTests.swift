import XCTest
@testable import LittleWatch

final class MenuBarFormatterTests: XCTestCase {
    private let snapshot = SystemMetricsSnapshot(
        cpuUsagePercent: 40.4,
        memoryUsagePercent: 79.6,
        diskUsagePercent: 38.2,
        diskFreeBytes: 184_240_000_000,
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    func testTitleJoinsEnabledFieldsWithSeparator() {
        var configuration = AppConfiguration.default
        configuration.fields[1].isEnabled = false
        configuration.fields[2].isEnabled = false
        configuration.fields[3].isEnabled = false

        let title = MenuBarFormatter().title(for: snapshot, configuration: configuration)

        XCTAssertEqual(title, "CPU 40%")
    }

    func testTitleShowsAllSystemMetricsByDefault() {
        let title = MenuBarFormatter().title(for: snapshot, configuration: .default)

        XCTAssertEqual(title, "CPU 40% · MEM 80% · DISK 38% · FREE 184.24 GB")
    }

    func testTitleUsesCustomLabelsWhenShowLabelsEnabled() {
        var configuration = AppConfiguration.default
        configuration.showLabels = true

        let title = MenuBarFormatter().title(for: snapshot, configuration: configuration)

        XCTAssertEqual(title, "CPU 40% · 内存 80% · 磁盘 38% · 剩余空间 184.24 GB")
    }

    func testRotatingDisplayModeShowsSingleFieldAtRotationIndex() {
        var configuration = AppConfiguration.default
        configuration.displayMode = .rotating

        let title = MenuBarFormatter().title(
            for: snapshot,
            configuration: configuration,
            rotationIndex: 1
        )

        XCTAssertEqual(title, "MEM 80%")
    }

    func testTitleFallsBackWhenAllFieldsDisabled() {
        var configuration = AppConfiguration.default
        configuration.fields = configuration.fields.map {
            var field = $0
            field.isEnabled = false
            return field
        }

        let title = MenuBarFormatter().title(for: snapshot, configuration: configuration)

        XCTAssertEqual(title, "Little Watch")
    }

    func testFormatDiskFreeRendersGigabytesWithTwoDecimals() {
        XCTAssertEqual(
            MenuBarFormatter().formatDiskFree(12_840_392_704),
            "FREE 12.84 GB"
        )
        XCTAssertEqual(MenuBarFormatter().formatDiskFree(-5), "FREE 0.00 GB")
    }

    func testConfigurationRoundTripsThroughJSON() throws {
        var configuration = AppConfiguration.default
        configuration.separator = .pipe
        configuration.showLabels = true
        configuration.displayMode = .rotating
        configuration.rotationIntervalSeconds = 10
        configuration.fields[0].label = "处理器"

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
    }

    func testLoadingLegacyConfigurationFallsBackToDefault() {
        let defaults = makeDefaults()
        let legacy = Data(
            """
            {"fields":[{"kind":"cost","isEnabled":true,"label":"消费"}],
             "separator":" | ","showLabels":false,
             "compactTokens":false,"costPrecision":1}
            """.utf8
        )
        defaults.set(legacy, forKey: "littlewatch.display.configuration.v1")

        let loaded = ConfigurationStore(defaults: defaults).load()

        XCTAssertEqual(loaded, .default)
    }

    func testLoadAppendsMissingMetricKinds() throws {
        let defaults = makeDefaults()
        let partial = AppConfiguration(fields: [
            DisplayFieldConfiguration(kind: .cpu, isEnabled: true, label: "CPU")
        ], separator: .dot, showLabels: false, displayMode: .fixed, rotationIntervalSeconds: 5)
        defaults.set(try JSONEncoder().encode(partial), forKey: "littlewatch.display.configuration.v1")

        let loaded = ConfigurationStore(defaults: defaults).load()

        XCTAssertEqual(loaded.fields.map(\.kind), MetricKind.allCases.map { $0 })
        XCTAssertTrue(loaded.fields.dropFirst().allSatisfy(\.isEnabled))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "LittleWatchTests.Configuration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

final class SystemMetricsMonitorTests: XCTestCase {
    func testDiskUsageParserMatchesDFOutput() throws {
        let output = """
        Filesystem     1024-blocks      Used Available Capacity Mounted on
        /dev/disk3s1s1   239362496  12012728  19407392    39%   /
        """

        let result = try XCTUnwrap(SystemMetricsMonitor.parseDiskUsage(output: output))

        XCTAssertEqual(result.usagePercent, 39)
        XCTAssertEqual(result.freeBytes, 19_407_392 * 1024)
    }

    func testDiskUsageParserRejectsMalformedOutput() {
        XCTAssertNil(SystemMetricsMonitor.parseDiskUsage(output: "Filesystem 1024-blocks"))
        XCTAssertNil(
            SystemMetricsMonitor.parseDiskUsage(
                output: "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk bad notanumber 39% /"
            )
        )
    }

    func testSampleReusesCachedDiskValuesWithinRefreshInterval() async {
        let diskSamples = LockedArray<(usagePercent: Double, freeBytes: Int64)>()
        let monitor = SystemMetricsMonitor(diskSampler: {
            diskSamples.append((usagePercent: 42, freeBytes: 9_876_543_210))
            return (usagePercent: 42, freeBytes: 9_876_543_210)
        })

        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = await monitor.sample(at: start)
        let second = await monitor.sample(at: start.addingTimeInterval(60))

        XCTAssertEqual(first.diskUsagePercent, 42)
        XCTAssertEqual(second.diskFreeBytes, 9_876_543_210)
        XCTAssertEqual(diskSamples.count, 1)
    }

    func testSampleRefreshesDiskAfterIntervalOrForcedRefresh() async {
        let diskSamples = LockedArray<(usagePercent: Double, freeBytes: Int64)>()
        let monitor = SystemMetricsMonitor(diskSampler: {
            let index = diskSamples.count
            let value = (usagePercent: Double(40 + index), freeBytes: Int64(1_000 + index))
            diskSamples.append(value)
            return value
        })

        let start = Date(timeIntervalSince1970: 2_000_000)
        let initial = await monitor.sample(at: start)
        _ = await monitor.sample(at: start.addingTimeInterval(60))
        let refreshed = await monitor.sample(
            at: start.addingTimeInterval(SystemMetricsMonitor.diskRefreshInterval)
        )
        let forced = await monitor.sample(at: start.addingTimeInterval(120), forceDiskRefresh: true)

        XCTAssertEqual(initial.diskUsagePercent, 40)
        XCTAssertEqual(refreshed.diskUsagePercent, 41)
        XCTAssertEqual(forced.diskUsagePercent, 42)
        XCTAssertEqual(forced.diskFreeBytes, 1_002)
        XCTAssertEqual(diskSamples.count, 3)
    }
}

private final class LockedArray<Element>: @unchecked Sendable {
    private var storage: [Element] = []
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func append(_ element: Element) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(element)
    }
}

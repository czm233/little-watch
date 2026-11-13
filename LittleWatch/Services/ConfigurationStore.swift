import Foundation

struct ConfigurationStore {
    private let defaults: UserDefaults
    private let key = "littlewatch.display.configuration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppConfiguration {
        guard
            let data = defaults.data(forKey: key),
            let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else {
            return .default
        }

        var migrated = configuration
        var seen = Set<MetricKind>()
        migrated.fields = migrated.fields.filter { seen.insert($0.kind).inserted }
        for kind in MetricKind.allCases where !seen.contains(kind) {
            migrated.fields.append(
                DisplayFieldConfiguration(
                    kind: kind,
                    isEnabled: kind.isEnabledByDefault,
                    label: kind.defaultLabel
                )
            )
        }
        migrated.rotationIntervalSeconds = [5, 10, 15].contains(migrated.rotationIntervalSeconds)
            ? migrated.rotationIntervalSeconds
            : 5
        return migrated
    }

    func save(_ configuration: AppConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }
}

struct MenuBarFormatter {
    func title(
        for systemSnapshot: SystemMetricsSnapshot,
        configuration: AppConfiguration,
        rotationIndex: Int = 0
    ) -> String {
        let enabledFields = configuration.fields.filter(\.isEnabled)
        let displayedFields: [DisplayFieldConfiguration]
        if configuration.displayMode == .rotating, !enabledFields.isEmpty {
            displayedFields = [enabledFields[rotationIndex % enabledFields.count]]
        } else {
            displayedFields = enabledFields
        }

        let values = displayedFields.map { field -> String in
            let value: String
            switch field.kind {
            case .cpu:
                value = formatPercent(systemSnapshot.cpuUsagePercent, prefix: configuration.showLabels ? "" : "CPU")
            case .memory:
                value = formatPercent(systemSnapshot.memoryUsagePercent, prefix: configuration.showLabels ? "" : "MEM")
            case .diskUsage:
                value = formatPercent(systemSnapshot.diskUsagePercent, prefix: configuration.showLabels ? "" : "DISK")
            case .diskFree:
                let formatted = formatDiskFree(systemSnapshot.diskFreeBytes)
                value = configuration.showLabels
                    ? formatted.replacingOccurrences(of: "FREE ", with: "")
                    : formatted
            }

            return configuration.showLabels ? "\(field.label) \(value)" : value
        }

        return values.isEmpty ? "Little Watch" : values.joined(separator: configuration.separator.rawValue)
    }

    func formatPercent(_ value: Double, prefix: String) -> String {
        let percent = "\(Int(value.rounded()))%"
        return prefix.isEmpty ? percent : "\(prefix) \(percent)"
    }

    func formatDiskFree(_ bytes: Int64) -> String {
        let gigabytes = Double(max(bytes, 0)) / 1_000_000_000
        return String(format: "FREE %.2f GB", gigabytes)
    }
}

import Foundation

enum MetricKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case diskUsage
    case diskFree

    var id: String { rawValue }

    var defaultLabel: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "内存"
        case .diskUsage: "磁盘"
        case .diskFree: "剩余空间"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu.fill"
        case .memory: "memorychip.fill"
        case .diskUsage: "internaldrive.fill"
        case .diskFree: "externaldrive.badge.checkmark"
        }
    }

    var isEnabledByDefault: Bool { true }
}

struct DisplayFieldConfiguration: Codable, Equatable, Identifiable, Sendable {
    var kind: MetricKind
    var isEnabled: Bool
    var label: String

    var id: MetricKind { kind }
}

enum SeparatorStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case dot = " · "
    case pipe = " | "
    case space = "  "

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dot: "圆点"
        case .pipe: "竖线"
        case .space: "留白"
        }
    }
}

enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixed
    case rotating

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixed: "固定组合"
        case .rotating: "逐项轮换"
        }
    }
}

struct AppConfiguration: Codable, Equatable, Sendable {
    var fields: [DisplayFieldConfiguration]
    var separator: SeparatorStyle
    var showLabels: Bool
    var displayMode: MenuBarDisplayMode
    var rotationIntervalSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case fields, separator, showLabels
        case displayMode, rotationIntervalSeconds
    }

    init(
        fields: [DisplayFieldConfiguration],
        separator: SeparatorStyle,
        showLabels: Bool,
        displayMode: MenuBarDisplayMode,
        rotationIntervalSeconds: Int
    ) {
        self.fields = fields
        self.separator = separator
        self.showLabels = showLabels
        self.displayMode = displayMode
        self.rotationIntervalSeconds = rotationIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fields = try container.decode([DisplayFieldConfiguration].self, forKey: .fields)
        separator = try container.decode(SeparatorStyle.self, forKey: .separator)
        showLabels = try container.decode(Bool.self, forKey: .showLabels)
        displayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .displayMode) ?? .fixed
        rotationIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .rotationIntervalSeconds) ?? 5
    }

    static let `default` = AppConfiguration(
        fields: MetricKind.allCases.map {
            DisplayFieldConfiguration(kind: $0, isEnabled: $0.isEnabledByDefault, label: $0.defaultLabel)
        },
        separator: .dot,
        showLabels: false,
        displayMode: .fixed,
        rotationIntervalSeconds: 5
    )
}

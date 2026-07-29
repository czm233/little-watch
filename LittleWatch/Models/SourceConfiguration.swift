import Foundation

struct SourceConfiguration: Codable, Equatable, Sendable {
    var baseURLString: String
    var password: String
    var pollingIntervalSeconds: Int
    var overviewRange: String
    var realtimeWindow: String

    static let `default` = SourceConfiguration(
        baseURLString: "",
        password: "",
        pollingIntervalSeconds: 5,
        overviewRange: "today",
        realtimeWindow: "60m"
    )

    init(
        baseURLString: String,
        password: String,
        pollingIntervalSeconds: Int,
        overviewRange: String,
        realtimeWindow: String
    ) {
        self.baseURLString = baseURLString
        self.password = password
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.overviewRange = overviewRange
        self.realtimeWindow = realtimeWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURLString = try container.decode(String.self, forKey: .baseURLString)
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        pollingIntervalSeconds = try container.decode(Int.self, forKey: .pollingIntervalSeconds)
        overviewRange = try container.decode(String.self, forKey: .overviewRange)
        realtimeWindow = try container.decode(String.self, forKey: .realtimeWindow)
    }

    func validatedBaseURL() throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            components.host != nil,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw SourceConfigurationError.invalidBaseURL
        }

        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"
        guard let url = components.url else {
            throw SourceConfigurationError.invalidBaseURL
        }
        return url
    }

    var usesPlainHTTP: Bool {
        URLComponents(string: baseURLString)?.scheme?.lowercased() == "http"
    }
}

enum SourceConfigurationError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "服务地址无效，只支持不含账号、查询参数的 HTTP 或 HTTPS 地址"
        case .missingPassword:
            "请先输入登录密码"
        }
    }
}

enum SourceConnectionState: Equatable {
    case needsCredential
    case connecting
    case reconnecting(String)
    case connected(Date)
    case failed(String)
}

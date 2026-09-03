import Foundation

enum CPAUsageKeeperError: LocalizedError, Equatable {
    case authenticationRequired
    case rateLimited
    case serverUnavailable(Int)
    case invalidResponse
    case responseTooLarge
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "登录失败，请检查密码"
        case .rateLimited:
            "请求过于频繁，请稍后再试"
        case let .serverUnavailable(status):
            "服务暂时不可用（HTTP \(status)）"
        case .invalidResponse:
            "服务返回了无法识别的响应"
        case .responseTooLarge:
            "服务响应超过安全大小限制"
        case let .network(message):
            "网络连接失败：\(message)"
        case let .decoding(message):
            "用量数据格式无法解析：\(message)"
        }
    }
}

actor CPAUsageKeeperClient {
    private static let maximumResponseBytes = 8 * 1_024 * 1_024

    private let baseURL: URL
    private let cookieStorage: HTTPCookieStorage
    private let session: URLSession
    private var authenticated = false

    init(baseURL: URL) {
        self.baseURL = baseURL

        let storage = URLSessionConfiguration.ephemeral.httpCookieStorage!
        for cookie in storage.cookies ?? [] {
            storage.deleteCookie(cookie)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = storage
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30

        cookieStorage = storage
        session = URLSession(configuration: configuration)
    }

    func fetchOverview(
        password: String,
        overviewRange: String,
        apiKeyID: String = ""
    ) async throws -> MetricOverviewSnapshot {
        if !authenticated {
            try await login(password: password)
        }

        do {
            return try await loadOverview(overviewRange: overviewRange, apiKeyID: apiKeyID)
        } catch CPAUsageKeeperError.authenticationRequired {
            clearSession()
            try await login(password: password)
            return try await loadOverview(overviewRange: overviewRange, apiKeyID: apiKeyID)
        }
    }

    func fetchRealtime(
        password: String,
        realtimeWindow: String,
        apiKeyID: String = ""
    ) async throws -> MetricRealtimeSnapshot {
        if !authenticated {
            try await login(password: password)
        }

        do {
            return try await loadRealtime(realtimeWindow: realtimeWindow, apiKeyID: apiKeyID)
        } catch CPAUsageKeeperError.authenticationRequired {
            clearSession()
            try await login(password: password)
            return try await loadRealtime(realtimeWindow: realtimeWindow, apiKeyID: apiKeyID)
        }
    }

    private func login(password: String) async throws {
        struct LoginBody: Encodable { let password: String }

        var request = URLRequest(url: endpointURL(path: "api/v1/auth/login"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(LoginBody(password: password))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("fetch", forHTTPHeaderField: "X-CPA-Usage-Keeper-Request")

        let (_, response) = try await perform(request, captureCookies: true)
        guard response.statusCode == 204 || response.statusCode == 200 else {
            throw CPAUsageKeeperError.invalidResponse
        }
        authenticated = true
    }

    private func loadOverview(overviewRange: String, apiKeyID: String) async throws -> MetricOverviewSnapshot {
        let resolvedAPIKeyID = try await resolveAPIKeyID(apiKeyID)
        let overview: CPAUsageOverviewResponse = try await get(
            path: "api/v1/usage/overview",
            query: usageQuery([URLQueryItem(name: "range", value: overviewRange)], apiKeyID: resolvedAPIKeyID)
        )
        let now = Date()

        return MetricOverviewSnapshot(
            costUSD: overview.summary.totalCost ?? 0,
            costAvailable: overview.summary.costAvailable ?? (overview.summary.totalCost != nil),
            tokenCount: overview.usage.totalTokens ?? overview.summary.tokenCount ?? 0,
            tokenCountAvailable: overview.usage.totalTokens != nil || overview.summary.tokenCount != nil,
            updatedAt: now,
            totalRequests: overview.usage.totalRequests,
            fallbackTokensPerMinute: overview.summary.tpm,
            fallbackRequestsPerMinute: overview.summary.rpm,
            projectedEndOfDayCostUSD: overviewRange == "today"
                ? UsageAnalytics.projectedEndOfDayCost(
                    currentCost: overview.summary.totalCost ?? 0,
                    at: now,
                    timeZoneIdentifier: overview.timezone
                )
                : nil
        )
    }

    private func loadRealtime(realtimeWindow: String, apiKeyID: String) async throws -> MetricRealtimeSnapshot {
        let resolvedAPIKeyID = try await resolveAPIKeyID(apiKeyID)
        let response: CPAUsageRealtimeResponse = try await get(
            path: "api/v1/usage/overview/realtime",
            query: usageQuery([URLQueryItem(name: "window", value: realtimeWindow)], apiKeyID: resolvedAPIKeyID)
        )
        let now = Date()
        let tpmTrend = ratePoints(
            response.tokenVelocity.map { ($0.bucket, $0.tokensPerMinute) },
            bucketSeconds: response.bucketSeconds,
            now: now
        )
        let rpmTrend = ratePoints(
            response.requestLevel.map { ($0.bucket, $0.requestsPerMinute) },
            bucketSeconds: response.bucketSeconds,
            now: now
        )

        return MetricRealtimeSnapshot(
            updatedAt: Date(),
            tokensPerMinuteTrend: tpmTrend,
            requestsPerMinuteTrend: rpmTrend,
            usageSpike: UsageAnalytics.detectSpike(
                tokensPerMinute: tpmTrend,
                requestsPerMinute: rpmTrend
            )
        )
    }

    private func usageQuery(_ query: [URLQueryItem], apiKeyID: String) -> [URLQueryItem] {
        let trimmed = apiKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return query }
        return query + [URLQueryItem(name: "api_key_id", value: trimmed)]
    }

    private func resolveAPIKeyID(_ selector: String) async throws -> String {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.allSatisfy(\.isNumber) { return trimmed }

        let response: CPAAPIKeySettingsListResponse = try await get(
            path: "api/v1/usage/api-keys/settings",
            query: []
        )
        guard let match = response.items.first(where: { $0.apiKey == trimmed }) else {
            throw CPAUsageKeeperError.decoding("找不到对应的 API Key，请检查输入是否为完整 Key 或数字 ID")
        }
        return match.id
    }

    private func ratePoints(
        _ values: [(bucket: String?, value: Double?)],
        bucketSeconds: Int?,
        now: Date
    ) -> [UsageRatePoint] {
        let interval = TimeInterval(max(bucketSeconds ?? 60, 1))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        return values.enumerated().compactMap { index, item in
            guard let value = item.value, value.isFinite, value >= 0 else { return nil }
            let timestamp = item.bucket.flatMap {
                formatter.date(from: $0) ?? fallbackFormatter.date(from: $0)
            } ?? now.addingTimeInterval(-Double(values.count - index - 1) * interval)
            return UsageRatePoint(timestamp: timestamp, value: value)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    private func get<Value: Decodable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> Value {
        var request = URLRequest(url: endpointURL(path: path, query: query))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        addCookies(to: &request)

        let (data, _) = try await perform(request)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw CPAUsageKeeperError.decoding(Self.decodingDescription(error))
        }
    }

    private func perform(
        _ request: URLRequest,
        captureCookies: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CPAUsageKeeperError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CPAUsageKeeperError.invalidResponse
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw CPAUsageKeeperError.responseTooLarge
        }

        switch http.statusCode {
        case 200..<300:
            if captureCookies { storeCookies(from: http) }
            return (data, http)
        case 401, 403:
            throw CPAUsageKeeperError.authenticationRequired
        case 429:
            throw CPAUsageKeeperError.rateLimited
        case 500...599:
            throw CPAUsageKeeperError.serverUnavailable(http.statusCode)
        default:
            throw CPAUsageKeeperError.invalidResponse
        }
    }

    private func endpointURL(path: String, query: [URLQueryItem] = []) -> URL {
        var url = baseURL
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard !query.isEmpty else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query
        return components.url!
    }

    private func addCookies(to request: inout URLRequest) {
        guard let url = request.url else { return }
        let cookies = cookieStorage.cookies(for: url) ?? []
        for (name, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private func storeCookies(from response: HTTPURLResponse) {
        guard let url = response.url else { return }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, header in
            guard let name = header.key as? String else { return }
            result[name] = String(describing: header.value)
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            cookieStorage.setCookie(cookie)
        }
    }

    private func clearSession() {
        authenticated = false
        for cookie in cookieStorage.cookies ?? [] {
            cookieStorage.deleteCookie(cookie)
        }
    }

    private static func decodingDescription(_ error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            "缺少字段 \((context.codingPath + [key]).map(\.stringValue).joined(separator: "."))"
        case let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context),
             let DecodingError.dataCorrupted(context):
            context.debugDescription
        default:
            error.localizedDescription
        }
    }

}

@MainActor
final class CPAUsageKeeperSource: MetricSource {
    let id = "cpa-usage-keeper"
    let displayName = "CPA Usage Keeper"

    private var configuration: SourceConfiguration
    private var client: CPAUsageKeeperClient

    init(configuration: SourceConfiguration) throws {
        self.configuration = configuration
        client = CPAUsageKeeperClient(baseURL: try configuration.validatedBaseURL())
    }

    func configure(_ configuration: SourceConfiguration) throws {
        let previousURL = try self.configuration.validatedBaseURL()
        let nextURL = try configuration.validatedBaseURL()
        let credentialsChanged = self.configuration.password != configuration.password
        self.configuration = configuration
        if previousURL != nextURL || credentialsChanged {
            client = CPAUsageKeeperClient(baseURL: nextURL)
        }
    }

    func fetchOverview() async throws -> MetricOverviewSnapshot {
        guard !configuration.password.isEmpty else {
            throw SourceConfigurationError.missingPassword
        }

        return try await client.fetchOverview(
            password: configuration.password,
            overviewRange: configuration.overviewRange,
            apiKeyID: configuration.apiKeyID
        )
    }

    func fetchRealtime() async throws -> MetricRealtimeSnapshot {
        guard !configuration.password.isEmpty else {
            throw SourceConfigurationError.missingPassword
        }

        return try await client.fetchRealtime(
            password: configuration.password,
            realtimeWindow: configuration.realtimeWindow,
            apiKeyID: configuration.apiKeyID
        )
    }

}

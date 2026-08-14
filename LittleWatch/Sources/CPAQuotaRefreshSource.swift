import Darwin
import Foundation

enum QuotaRefreshState: Equatable {
    case idle
    case refreshing
    case succeeded(Date)
    case failed(String)
}

enum CPAQuotaRefreshError: LocalizedError, Equatable {
    case authenticationRequired
    case rateLimited
    case serverUnavailable(Int)
    case invalidResponse
    case responseTooLarge
    case network(String)
    case decoding(String)
    case identityUnavailable
    case refreshInProgress
    case cooldown(Int)
    case redirectRejected
    case rejected(String)
    case taskFailed(String)
    case unexpectedTaskStatus(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "登录已失效，请重新连接 CPA Usage Keeper 后再试"
        case .rateLimited:
            "服务拒绝了频繁请求；本次额度更新不会自动重试"
        case let .serverUnavailable(status):
            "额度服务暂时不可用（HTTP \(status)）；本次请求不会自动重试"
        case .invalidResponse:
            "额度服务返回了无法识别的响应"
        case .responseTooLarge:
            "额度服务响应超过安全大小限制"
        case let .network(message):
            "额度更新网络连接失败：\(message)"
        case let .decoding(message):
            "额度数据格式无法解析：\(message)"
        case .identityUnavailable:
            "没有找到可更新额度的 Codex 凭证"
        case .refreshInProgress:
            "额度更新正在进行，请等待当前任务完成"
        case let .cooldown(seconds):
            "额度更新每分钟最多一次，请在 \(seconds) 秒后重试"
        case .redirectRejected:
            "额度服务要求重定向；为避免重复提交，本次更新已停止"
        case let .rejected(reason):
            "额度更新未被接受：\(reason)"
        case let .taskFailed(message):
            "额度更新失败：\(message)"
        case let .unexpectedTaskStatus(status):
            "额度服务返回了未知任务状态：\(status)"
        case .timedOut:
            "额度更新仍未完成，请稍后查看；本次请求不会自动重试"
        }
    }
}

struct CPAUsageIdentitiesPageResponse: Decodable, Equatable, Sendable {
    let identities: [CPAUsageIdentity]

    enum CodingKeys: String, CodingKey {
        case identities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identities = try container.decodeIfPresent([CPAUsageIdentity].self, forKey: .identities) ?? []
    }
}

struct CPAUsageIdentity: Decodable, Equatable, Sendable {
    let identity: String
    let type: String
    let provider: String
    let disabled: Bool
    let priority: Int?

    enum CodingKeys: String, CodingKey {
        case identity
        case type
        case provider
        case disabled
        case priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = try container.decode(String.self, forKey: .identity)
        type = try container.decode(String.self, forKey: .type)
        provider = try container.decode(String.self, forKey: .provider)
        disabled = try container.decode(Bool.self, forKey: .disabled)
        priority = try container.decodeFlexibleIntIfPresent(forKey: .priority)
    }
}

struct CPAQuotaRefreshStartResponse: Decodable, Equatable, Sendable {
    let tasks: [CPAQuotaRefreshTaskReference]
    let rejected: [CPAQuotaRefreshRejection]
    let accepted: Int?
    let skipped: Int?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case tasks
        case rejected
        case accepted
        case skipped
        case limit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decodeIfPresent([CPAQuotaRefreshTaskReference].self, forKey: .tasks) ?? []
        rejected = try container.decodeIfPresent([CPAQuotaRefreshRejection].self, forKey: .rejected) ?? []
        accepted = try container.decodeFlexibleIntIfPresent(forKey: .accepted)
        skipped = try container.decodeFlexibleIntIfPresent(forKey: .skipped)
        limit = try container.decodeFlexibleIntIfPresent(forKey: .limit)
    }
}

struct CPAQuotaRefreshTaskReference: Decodable, Equatable, Sendable {
    let authIndex: String
}

struct CPAQuotaRefreshRejection: Decodable, Equatable, Sendable {
    let authIndex: String
    let error: String
}

enum CPAQuotaRefreshTaskStatus: Equatable, Sendable {
    case queued
    case running
    case completed
    case failed
    case unknown(String)

    init(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "queued": self = .queued
        case "running": self = .running
        case "completed": self = .completed
        case "failed": self = .failed
        default: self = .unknown(normalized.isEmpty ? "空状态" : normalized)
        }
    }
}

struct CPAQuotaRefreshTaskResponse: Decodable, Equatable, Sendable {
    let authIndex: String
    let fileName: String?
    let status: CPAQuotaRefreshTaskStatus
    let quota: CPAQuotaPayload?
    let error: String?
    let httpStatusCode: Int?
    let refreshedAt: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case authIndex
        case fileName = "file_name"
        case status
        case quota
        case error
        case httpStatusCode = "http_status_code"
        case refreshedAt = "refreshed_at"
        case expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authIndex = try container.decodeIfPresent(String.self, forKey: .authIndex) ?? ""
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        status = CPAQuotaRefreshTaskStatus(
            rawValue: try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        )
        quota = try container.decodeIfPresent(CPAQuotaPayload.self, forKey: .quota)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        httpStatusCode = try container.decodeFlexibleIntIfPresent(forKey: .httpStatusCode)
        refreshedAt = try container.decodeIfPresent(String.self, forKey: .refreshedAt)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}

struct CPAQuotaPayload: Decodable, Equatable, Sendable {
    let id: String?
    let items: [CPAQuotaItem]
    let rateLimitResetCreditsAvailableCount: Int?

    /// The CPA response reports usage for the primary weekly window. The UI is
    /// interested in the remaining allowance, so keep the selection logic next
    /// to the decoded payload instead of duplicating it in each view.
    var weeklyPrimaryWindow: CPAQuotaItem? {
        items.first(where: { $0.key == "rate_limit.primary_window" })
            ?? items.first(where: {
                $0.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "weekly"
                    && $0.scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "window"
            })
    }

    var weeklyRemainingPercent: Double? {
        weeklyPrimaryWindow?.remainingPercent
    }

    enum CodingKeys: String, CodingKey {
        case id
        case items = "quota"
        case rateLimitResetCreditsAvailableCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        items = try container.decodeIfPresent([CPAQuotaItem].self, forKey: .items) ?? []
        rateLimitResetCreditsAvailableCount = try container.decodeFlexibleIntIfPresent(
            forKey: .rateLimitResetCreditsAvailableCount
        )
    }
}

struct CPAQuotaItem: Decodable, Equatable, Sendable {
    let key: String?
    let label: String?
    let scope: String?
    let metric: String?
    let planType: String?
    let usedPercent: Double?
    let allowed: Bool?
    let limitReached: Bool?
    let window: CPAQuotaWindow?
    let resetAt: String?
    let resetAfterSeconds: Int?
    let windowUsageTokens: Int?
    let windowUsageCost: Double?

    /// `usedPercent` is the percentage consumed, while the product UI shows
    /// the percentage still available (for example, 2 used -> 98 remaining).
    var remainingPercent: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(max(100 - usedPercent, 0), 100)
    }

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case scope
        case metric
        case planType
        case usedPercent
        case allowed
        case limitReached
        case window
        case resetAt
        case resetAfterSeconds
        case windowUsageTokens = "window_usage_tokens"
        case windowUsageCost = "window_usage_cost"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        metric = try container.decodeIfPresent(String.self, forKey: .metric)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        usedPercent = try container.decodeFlexibleDoubleIfPresent(forKey: .usedPercent)
        allowed = try container.decodeIfPresent(Bool.self, forKey: .allowed)
        limitReached = try container.decodeIfPresent(Bool.self, forKey: .limitReached)
        window = try container.decodeIfPresent(CPAQuotaWindow.self, forKey: .window)
        resetAt = try container.decodeIfPresent(String.self, forKey: .resetAt)
        resetAfterSeconds = try container.decodeFlexibleIntIfPresent(forKey: .resetAfterSeconds)
        windowUsageTokens = try container.decodeFlexibleIntIfPresent(forKey: .windowUsageTokens)
        windowUsageCost = try container.decodeFlexibleDoubleIfPresent(forKey: .windowUsageCost)
    }
}

struct CPAQuotaWindow: Decodable, Equatable, Sendable {
    let duration: Double?
    let unit: String?
    let seconds: Int?

    enum CodingKeys: String, CodingKey {
        case duration
        case unit
        case seconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeFlexibleDoubleIfPresent(forKey: .duration)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        seconds = try container.decodeFlexibleIntIfPresent(forKey: .seconds)
    }
}

struct CPAQuotaRefreshResult: Equatable, Sendable {
    let authIndex: String
    let refreshedAt: Date
    let quota: CPAQuotaPayload
}

protocol CPAQuotaRefreshTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class NoRedirectQuotaSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Return the 3xx response to the caller. This guarantees that URLSession cannot
        // replay the quota POST and keeps every request on the configured service origin.
        completionHandler(nil)
    }
}

final class URLSessionCPAQuotaRefreshTransport: CPAQuotaRefreshTransport, @unchecked Sendable {
    private let delegate: NoRedirectQuotaSessionDelegate
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let delegate = NoRedirectQuotaSessionDelegate()
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CPAQuotaRefreshError.invalidResponse
        }
        return (data, http)
    }

}

final class QuotaRefreshCooldownStore: @unchecked Sendable {
    private static let lock = NSLock()
    static let globalIdentifier = "littlewatch.quota-refresh.global"

    private let defaults: UserDefaults
    private let storageKey: String
    private let lockFileURL: URL?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "littlewatch.quota-refresh.last-attempt.v1",
        lockFileURL: URL? = QuotaRefreshCooldownStore.defaultLockFileURL()
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.lockFileURL = lockFileURL
    }

    func remainingSeconds(
        at date: Date,
        for serviceIdentifier: String,
        cooldown: TimeInterval
    ) -> Int {
        withExclusiveLock { descriptor in
            remainingSecondsLocked(
                at: date,
                for: serviceIdentifier,
                cooldown: cooldown,
                fileDescriptor: descriptor
            )
        } ?? Int(ceil(cooldown))
    }

    /// Atomically reserves the next quota POST across app processes.
    /// The timestamp is stored before network dispatch, so failures still consume the cooldown.
    func consumeAttempt(
        at date: Date,
        for serviceIdentifier: String,
        cooldown: TimeInterval
    ) -> Int {
        withExclusiveLock { descriptor in
            let remaining = remainingSecondsLocked(
                at: date,
                for: serviceIdentifier,
                cooldown: cooldown,
                fileDescriptor: descriptor
            )
            guard remaining == 0 else { return remaining }

            if let descriptor, !writeTimestamp(date.timeIntervalSince1970, to: descriptor) {
                return Int(ceil(cooldown))
            }

            var values = defaults.dictionary(forKey: storageKey) ?? [:]
            values[serviceIdentifier] = date.timeIntervalSince1970
            defaults.set(values, forKey: storageKey)
            defaults.synchronize()
            return 0
        } ?? Int(ceil(cooldown))
    }

    private func remainingSecondsLocked(
        at date: Date,
        for serviceIdentifier: String,
        cooldown: TimeInterval,
        fileDescriptor: Int32? = nil
    ) -> Int {
        let defaultsTimestamp = (defaults.dictionary(forKey: storageKey)?[serviceIdentifier] as? NSNumber)?
            .doubleValue
        let fileTimestamp = fileDescriptor.flatMap(readTimestamp)
        if let fileTimestamp, !fileTimestamp.isFinite {
            return Int(ceil(cooldown))
        }
        guard let timestamp = [defaultsTimestamp, fileTimestamp]
            .compactMap({ $0 })
            .filter(\.isFinite)
            .max()
        else {
            return 0
        }

        let elapsed = max(0, date.timeIntervalSince1970 - timestamp)
        return min(Int(ceil(cooldown)), Int(ceil(max(0, cooldown - elapsed))))
    }

    private func withExclusiveLock<T>(_ body: (Int32?) -> T) -> T? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        guard let lockFileURL else { return body(nil) }
        let directoryURL = lockFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        _ = fchmod(descriptor, S_IRUSR | S_IWUSR)

        var fileLock = Darwin.flock(
            l_start: 0,
            l_len: 0,
            l_pid: 0,
            l_type: Int16(F_WRLCK),
            l_whence: Int16(SEEK_SET)
        )
        guard fcntl(descriptor, F_SETLKW, &fileLock) != -1 else { return nil }
        defer {
            fileLock.l_type = Int16(F_UNLCK)
            _ = fcntl(descriptor, F_SETLK, &fileLock)
        }
        defaults.synchronize()
        return body(descriptor)
    }

    private func readTimestamp(from descriptor: Int32) -> Double? {
        var bytes = [UInt8](repeating: 0, count: 64)
        let count = bytes.withUnsafeMutableBytes { buffer in
            pread(descriptor, buffer.baseAddress, buffer.count, 0)
        }
        guard count >= 0 else { return .nan }
        guard count > 0 else { return nil }
        return Double(String(decoding: bytes.prefix(Int(count)), as: UTF8.self)) ?? .nan
    }

    private func writeTimestamp(_ timestamp: Double, to descriptor: Int32) -> Bool {
        let data = Data(String(timestamp).utf8)
        guard ftruncate(descriptor, 0) == 0 else { return false }
        let count = data.withUnsafeBytes { buffer in
            pwrite(descriptor, buffer.baseAddress, buffer.count, 0)
        }
        guard count == data.count else { return false }
        return fsync(descriptor) == 0
    }

    private static func defaultLockFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LittleWatch", isDirectory: true)
            .appendingPathComponent("quota-refresh.lock", isDirectory: false)
    }
}

actor CPAQuotaRefreshClient {
    static let cooldownSeconds: TimeInterval = 60
    static let pollInterval: Duration = .seconds(5)
    static let maximumPolls = 8

    private static let maximumResponseBytes = 8 * 1_024 * 1_024

    private let baseURL: URL
    private let transport: any CPAQuotaRefreshTransport
    private let cooldownStore: QuotaRefreshCooldownStore
    private let currentDate: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var authenticated = false
    private var isRefreshing = false

    init(
        baseURL: URL,
        transport: any CPAQuotaRefreshTransport = URLSessionCPAQuotaRefreshTransport(),
        cooldownStore: QuotaRefreshCooldownStore = QuotaRefreshCooldownStore(),
        currentDate: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.cooldownStore = cooldownStore
        self.currentDate = currentDate
        self.sleep = sleep
    }

    func cooldownRemainingSeconds() -> Int {
        cooldownStore.remainingSeconds(
            at: currentDate(),
            for: QuotaRefreshCooldownStore.globalIdentifier,
            cooldown: Self.cooldownSeconds
        )
    }

    func refreshHighestPriorityCodexQuota(password: String) async throws -> CPAQuotaRefreshResult {
        guard !isRefreshing else { throw CPAQuotaRefreshError.refreshInProgress }
        isRefreshing = true
        defer { isRefreshing = false }

        let initialRemaining = cooldownRemainingSeconds()
        guard initialRemaining == 0 else {
            throw CPAQuotaRefreshError.cooldown(initialRemaining)
        }

        let authIndex = try await loadHighestPriorityCodexAuthIndex(password: password)

        // This is the only path that can authorize a quota POST. The persisted timestamp is
        // consumed immediately before dispatch and is not rolled back for any failure.
        let remaining = cooldownStore.consumeAttempt(
            at: currentDate(),
            for: QuotaRefreshCooldownStore.globalIdentifier,
            cooldown: Self.cooldownSeconds
        )
        guard remaining == 0 else { throw CPAQuotaRefreshError.cooldown(remaining) }

        let submission = try await startQuotaRefresh(authIndex: authIndex)
        let taskAuthIndex = try taskAuthIndex(from: submission, requested: authIndex)

        for pollIndex in 0..<Self.maximumPolls {
            try Task.checkCancellation()
            let task: CPAQuotaRefreshTaskResponse = try await get(
                path: "api/v1/quota/refresh/\(taskAuthIndex)",
                query: []
            )
            guard task.authIndex == taskAuthIndex else {
                throw CPAQuotaRefreshError.invalidResponse
            }

            switch task.status {
            case .completed:
                guard
                    let quota = task.quota,
                    quota.id == taskAuthIndex,
                    let refreshedAtText = task.refreshedAt,
                    let refreshedAt = Self.parseServerDate(refreshedAtText)
                else {
                    throw CPAQuotaRefreshError.invalidResponse
                }
                return CPAQuotaRefreshResult(
                    authIndex: taskAuthIndex,
                    refreshedAt: refreshedAt,
                    quota: quota
                )
            case .failed:
                let message = task.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw CPAQuotaRefreshError.taskFailed(
                    message.flatMap { $0.isEmpty ? nil : $0 } ?? "服务未返回失败原因"
                )
            case .queued, .running:
                if pollIndex < Self.maximumPolls - 1 {
                    try await sleep(Self.pollInterval)
                }
            case let .unknown(status):
                throw CPAQuotaRefreshError.unexpectedTaskStatus(status)
            }
        }
        throw CPAQuotaRefreshError.timedOut
    }

    private func loadHighestPriorityCodexAuthIndex(password: String) async throws -> String {
        if !authenticated {
            try await login(password: password)
        }

        do {
            return try await requestHighestPriorityCodexAuthIndex()
        } catch CPAQuotaRefreshError.authenticationRequired {
            // Only the read-only identity lookup is retried after re-authentication.
            authenticated = false
            try await login(password: password)
            return try await requestHighestPriorityCodexAuthIndex()
        }
    }

    private func requestHighestPriorityCodexAuthIndex() async throws -> String {
        let response: CPAUsageIdentitiesPageResponse = try await get(
            path: "api/v1/usage/identities/page",
            query: [
                URLQueryItem(name: "auth_type", value: "1"),
                URLQueryItem(name: "active_only", value: "true"),
                URLQueryItem(name: "type", value: "codex"),
                URLQueryItem(name: "sort", value: "priority"),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "page_size", value: "1")
            ]
        )
        guard let identity = response.identities.first(where: { item in
            guard !item.disabled else { return false }
            return item.type.caseInsensitiveCompare("codex") == .orderedSame
        }) else {
            throw CPAQuotaRefreshError.identityUnavailable
        }

        let authIndex = identity.identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafePathComponent(authIndex) else {
            throw CPAQuotaRefreshError.identityUnavailable
        }
        return authIndex
    }

    private func login(password: String) async throws {
        struct LoginBody: Encodable {
            let password: String
        }

        var request = URLRequest(url: endpointURL(path: "api/v1/auth/login"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(LoginBody(password: password))
        addJSONHeaders(to: &request, mutating: true)
        _ = try await perform(request)
        authenticated = true
    }

    private func startQuotaRefresh(authIndex: String) async throws -> CPAQuotaRefreshStartResponse {
        struct RefreshBody: Encodable {
            let authIndexes: [String]

            enum CodingKeys: String, CodingKey {
                case authIndexes = "auth_indexes"
            }
        }

        var request = URLRequest(url: endpointURL(path: "api/v1/quota/refresh"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(RefreshBody(authIndexes: [authIndex]))
        addJSONHeaders(to: &request, mutating: true)

        // Never re-authenticate and replay this POST. A lost response may still mean that
        // the server accepted it, so a future attempt must come from another user click.
        return try await decodeResponse(CPAQuotaRefreshStartResponse.self, for: request)
    }

    private func get<Value: Decodable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> Value {
        var request = URLRequest(url: endpointURL(path: path, query: query))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decodeResponse(Value.self, for: request)
    }

    private func decodeResponse<Value: Decodable>(
        _ type: Value.Type,
        for request: URLRequest
    ) async throws -> Value {
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CPAQuotaRefreshError.decoding(Self.decodingDescription(error))
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as CPAQuotaRefreshError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CPAQuotaRefreshError.network(error.localizedDescription)
        }

        guard response.url == request.url else {
            throw CPAQuotaRefreshError.invalidResponse
        }

        guard data.count <= Self.maximumResponseBytes else {
            throw CPAQuotaRefreshError.responseTooLarge
        }
        switch response.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw CPAQuotaRefreshError.authenticationRequired
        case 429:
            throw CPAQuotaRefreshError.rateLimited
        case 500...599:
            throw CPAQuotaRefreshError.serverUnavailable(response.statusCode)
        case 300...399:
            throw CPAQuotaRefreshError.redirectRejected
        default:
            throw CPAQuotaRefreshError.invalidResponse
        }
    }

    private func taskAuthIndex(
        from response: CPAQuotaRefreshStartResponse,
        requested authIndex: String
    ) throws -> String {
        if let task = response.tasks.first(where: { $0.authIndex == authIndex }) {
            return task.authIndex
        }
        if response.rejected.contains(where: {
            $0.authIndex == authIndex && $0.error.lowercased() == "duplicate"
        }) {
            // A duplicate means the server already owns a task; only read-only polling follows.
            return authIndex
        }
        if let rejection = response.rejected.first(where: { $0.authIndex == authIndex }) {
            throw CPAQuotaRefreshError.rejected(Self.rejectionMessage(rejection.error))
        }
        throw CPAQuotaRefreshError.invalidResponse
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

    private func addJSONHeaders(to request: inout URLRequest, mutating: Bool) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if mutating {
            request.setValue("fetch", forHTTPHeaderField: "X-CPA-Usage-Keeper-Request")
        }
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func parseServerDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func rejectionMessage(_ code: String) -> String {
        switch code.lowercased() {
        case "not_found": "未找到对应凭证"
        case "not_auth_file": "该身份不是可更新的凭证文件"
        case "unsupported": "当前凭证类型不支持额度更新"
        case "duplicate_request": "请求中包含重复凭证"
        case "invalid": "凭证标识无效"
        default: code
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
final class CPAQuotaRefreshSource {
    private var configuration: SourceConfiguration
    private var client: CPAQuotaRefreshClient

    init(configuration: SourceConfiguration) throws {
        self.configuration = configuration
        client = CPAQuotaRefreshClient(baseURL: try configuration.validatedBaseURL())
    }

    func configure(_ configuration: SourceConfiguration) throws {
        let previousURL = try self.configuration.validatedBaseURL()
        let nextURL = try configuration.validatedBaseURL()
        let credentialsChanged = self.configuration.password != configuration.password
        self.configuration = configuration
        if previousURL != nextURL || credentialsChanged {
            client = CPAQuotaRefreshClient(baseURL: nextURL)
        }
    }

    func refreshHighestPriorityCodexQuota() async throws -> CPAQuotaRefreshResult {
        guard !configuration.password.isEmpty else {
            throw SourceConfigurationError.missingPassword
        }
        return try await client.refreshHighestPriorityCodexQuota(password: configuration.password)
    }

    func cooldownRemainingSeconds() async -> Int {
        await client.cooldownRemainingSeconds()
    }
}

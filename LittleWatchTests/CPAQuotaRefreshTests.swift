import Foundation
import XCTest
@testable import LittleWatch

final class CPAQuotaRefreshTests: XCTestCase {
    @MainActor
    func testAutomaticQuotaRefreshRunsEveryFiveMinutes() {
        let interval = AppStore.quotaRefreshIntervalSeconds
        XCTAssertEqual(interval, 300)
    }

    func testRefreshPostsOneCodexIdentityAndPollsUntilCompleted() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let sleeper = DurationRecorder()
        let transport = ScriptedQuotaTransport { request, count in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/auth/login"):
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "X-CPA-Usage-Keeper-Request"),
                    "fetch"
                )
                return Self.response(for: request, body: "{}")
            case ("GET", "/api/v1/usage/identities/page"):
                let components = try XCTUnwrap(
                    URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                )
                let query = Dictionary(
                    uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
                )
                XCTAssertEqual(
                    query,
                    [
                        "auth_type": "1",
                        "active_only": "true",
                        "type": "codex",
                        "sort": "priority",
                        "page": "1",
                        "page_size": "1"
                    ]
                )
                return Self.response(
                    for: request,
                    body: #"{"identities":[{"identity":"auth-codex","type":"codex","provider":"codex","disabled":false,"priority":100}]}"#
                )
            case ("POST", "/api/v1/quota/refresh"):
                XCTAssertEqual(count, 3)
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "X-CPA-Usage-Keeper-Request"),
                    "fetch"
                )
                let body = try Self.requestBody(from: request)
                let object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: [String]]
                )
                XCTAssertEqual(object, ["auth_indexes": ["auth-codex"]])
                return Self.response(
                    for: request,
                    body: #"{"tasks":[{"authIndex":"auth-codex"}],"rejected":null,"accepted":1,"skipped":0,"limit":1}"#
                )
            case ("GET", "/api/v1/quota/refresh/auth-codex"):
                if count == 4 {
                    return Self.response(
                        for: request,
                        body: #"{"authIndex":"auth-codex","file_name":"codex-test.json","status":"running"}"#
                    )
                }
                return Self.response(
                    for: request,
                    body: #"{"authIndex":"auth-codex","file_name":"codex-test.json","status":"completed","quota":{"id":"auth-codex","quota":[{"key":"rate_limit.primary_window","label":"Weekly","usedPercent":38,"allowed":true,"limitReached":false,"window":{"seconds":604800},"window_usage_tokens":315453933,"window_usage_cost":210.9636206}],"rateLimitResetCreditsAvailableCount":0},"refreshed_at":"2026-08-13T09:59:14.450644747+08:00"}"#
                )
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let client = CPAQuotaRefreshClient(
            baseURL: URL(string: "https://keeper.example")!,
            transport: transport,
            cooldownStore: makeCooldownStore(defaults: defaults),
            currentDate: { clock.now },
            sleep: { duration in await sleeper.record(duration) }
        )

        let result = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
        let requests = await transport.recordedRequests()
        let delays = await sleeper.recordedDurations()
        let remaining = await client.cooldownRemainingSeconds()

        XCTAssertEqual(result.authIndex, "auth-codex")
        XCTAssertEqual(result.quota.items.first?.usedPercent, 38)
        XCTAssertEqual(result.quota.weeklyRemainingPercent, 62)
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/quota/refresh" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/quota/refresh/auth-codex" }.count, 2)
        XCTAssertEqual(delays, [.seconds(5)])
        XCTAssertEqual(remaining, 60)
    }

    func testWeeklyRemainingPercentUsesPrimaryWindowAndClampsToValidRange() throws {
        let payload = try JSONDecoder().decode(
            CPAQuotaPayload.self,
            from: Data("{\"id\":\"auth-codex\",\"quota\":[{\"key\":\"rate_limit.primary_window\",\"label\":\"Weekly\",\"scope\":\"window\",\"usedPercent\":2},{\"key\":\"additional_rates\",\"label\":\"GPT Weekly\",\"scope\":\"additional\",\"usedPercent\":90}]}".utf8)
        )

        XCTAssertEqual(payload.weeklyRemainingPercent, 98)

        let exhausted = try JSONDecoder().decode(
            CPAQuotaPayload.self,
            from: Data(#"{"id":"auth-codex","quota":[{"label":"Weekly","scope":"window","usedPercent":120}]}"#.utf8)
        )
        XCTAssertEqual(exhausted.weeklyRemainingPercent, 0)
    }

    func testLatestHARWeeklyResponseReportsNinetyNinePercentRemaining() throws {
        let payload = try JSONDecoder().decode(
            CPAQuotaPayload.self,
            from: Data(
                #"{"id":"fdd559d47ad9838c","quota":[{"key":"rate_limit.primary_window","label":"Weekly","scope":"window","planType":"pro","usedPercent":1,"allowed":true,"limitReached":false,"window":{"seconds":604800},"resetAt":"2026-08-20T11:32:23+08:00","resetAfterSeconds":594222,"window_usage_tokens":72610404,"window_usage_cost":36.1703696},{"key":"additional_rate_limits.GPT-5.3-Codex-Spark.primary_window","label":"GPT-5.3-Codex-Spark Weekly","scope":"additional","metric":"codex_bengalfox","planType":"pro","usedPercent":0,"allowed":true,"limitReached":false,"window":{"seconds":604800},"resetAt":"2026-08-20T14:28:42+08:00","resetAfterSeconds":604800}],"rateLimitResetCreditsAvailableCount":0}"#.utf8
            )
        )

        XCTAssertEqual(payload.weeklyRemainingPercent, 99)
        XCTAssertEqual(payload.items.first?.remainingPercent, 99)
        XCTAssertEqual(payload.items.dropFirst().first?.remainingPercent, 100)
    }

    func testImmediateSecondRefreshIsBlockedBeforeNetwork() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let transport = successfulTransport()
        let client = makeClient(transport: transport, defaults: defaults, clock: clock)

        _ = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
        let countAfterFirstRefresh = await transport.requestCount()

        do {
            _ = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
            XCTFail("Expected persisted cooldown")
        } catch let error as CPAQuotaRefreshError {
            XCTAssertEqual(error, .cooldown(60))
        }

        let finalCount = await transport.requestCount()
        XCTAssertEqual(finalCount, countAfterFirstRefresh)
    }

    func testFailedRefreshPostStillConsumesCooldownAndIsNeverReplayed() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let transport = ScriptedQuotaTransport { request, _ in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/auth/login"):
                return Self.response(for: request, body: "{}")
            case ("GET", "/api/v1/usage/identities/page"):
                return Self.response(
                    for: request,
                    body: #"{"identities":[{"identity":"auth-codex","type":"codex","provider":"codex","disabled":false}]}"#
                )
            case ("POST", "/api/v1/quota/refresh"):
                return Self.response(for: request, status: 500, body: #"{"error":"temporary"}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let client = makeClient(transport: transport, defaults: defaults, clock: clock)

        do {
            _ = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
            XCTFail("Expected server failure")
        } catch let error as CPAQuotaRefreshError {
            XCTAssertEqual(error, .serverUnavailable(500))
        }
        do {
            _ = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
            XCTFail("Expected cooldown after failed POST")
        } catch let error as CPAQuotaRefreshError {
            XCTAssertEqual(error, .cooldown(60))
        }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/quota/refresh" }.count, 1)
    }

    func testUnauthorizedRefreshPostIsNotAutomaticallyReplayed() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let transport = ScriptedQuotaTransport { request, _ in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/auth/login"):
                return Self.response(for: request, body: "{}")
            case ("GET", "/api/v1/usage/identities/page"):
                return Self.response(
                    for: request,
                    body: #"{"identities":[{"identity":"auth-codex","type":"codex","provider":"codex","disabled":false}]}"#
                )
            case ("POST", "/api/v1/quota/refresh"):
                return Self.response(for: request, status: 401, body: #"{"error":"unauthorized"}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let client = makeClient(transport: transport, defaults: defaults, clock: clock)

        do {
            _ = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
            XCTFail("Expected authentication failure")
        } catch let error as CPAQuotaRefreshError {
            XCTAssertEqual(error, .authenticationRequired)
        }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/auth/login" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/quota/refresh" }.count, 1)
    }

    func testConcurrentRefreshesProduceOnlyOneQuotaPost() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let transport = successfulTransport()
        let client = makeClient(transport: transport, defaults: defaults, clock: clock)

        let results = await withTaskGroup(of: Result<CPAQuotaRefreshResult, Error>.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    do {
                        return .success(
                            try await client.refreshHighestPriorityCodexQuota(password: "test-password")
                        )
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var values: [Result<CPAQuotaRefreshResult, Error>] = []
            for await value in group { values.append(value) }
            return values
        }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/quota/refresh" }.count, 1)
        XCTAssertEqual(results.filter { if case .success = $0 { true } else { false } }.count, 1)
    }

    func testCooldownExpiresAtExactlySixtySecondsAndSurvivesStoreRecreation() throws {
        let suiteName = "CPAQuotaRefreshTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Cannot create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = Date(timeIntervalSince1970: 1_786_560_000)
        let store = makeCooldownStore(defaults: defaults)
        XCTAssertEqual(
            store.consumeAttempt(
                at: start,
                for: QuotaRefreshCooldownStore.globalIdentifier,
                cooldown: 60
            ),
            0
        )
        XCTAssertEqual(
            store.remainingSeconds(
                at: start.addingTimeInterval(59.999),
                for: QuotaRefreshCooldownStore.globalIdentifier,
                cooldown: 60
            ),
            1
        )

        let recreated = makeCooldownStore(defaults: defaults)
        XCTAssertEqual(
            recreated.remainingSeconds(
                at: start.addingTimeInterval(60),
                for: QuotaRefreshCooldownStore.globalIdentifier,
                cooldown: 60
            ),
            0
        )
    }

    func testCompletedTaskWithoutQuotaIsRejected() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let transport = ScriptedQuotaTransport { request, _ in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/auth/login"):
                return Self.response(for: request, body: "{}")
            case ("GET", "/api/v1/usage/identities/page"):
                return Self.response(
                    for: request,
                    body: #"{"identities":[{"identity":"auth-codex","type":"codex","provider":"codex","disabled":false}]}"#
                )
            case ("POST", "/api/v1/quota/refresh"):
                return Self.response(
                    for: request,
                    body: #"{"tasks":[{"authIndex":"auth-codex"}],"rejected":[],"accepted":1}"#
                )
            case ("GET", "/api/v1/quota/refresh/auth-codex"):
                return Self.response(
                    for: request,
                    body: #"{"authIndex":"auth-codex","status":"completed"}"#
                )
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let client = makeClient(transport: transport, defaults: defaults, clock: clock)

        do {
            _ = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
            XCTFail("Expected invalid completed response")
        } catch let error as CPAQuotaRefreshError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testTwoIndependentClientsShareOneGlobalQuotaPostReservation() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let transportA = successfulTransport()
        let transportB = successfulTransport()
        let clientA = makeClient(transport: transportA, defaults: defaults, clock: clock)
        let clientB = makeClient(transport: transportB, defaults: defaults, clock: clock)

        let results = await withTaskGroup(of: Result<CPAQuotaRefreshResult, Error>.self) { group in
            group.addTask {
                do {
                    return .success(
                        try await clientA.refreshHighestPriorityCodexQuota(password: "test-password")
                    )
                } catch { return .failure(error) }
            }
            group.addTask {
                do {
                    return .success(
                        try await clientB.refreshHighestPriorityCodexQuota(password: "test-password")
                    )
                } catch { return .failure(error) }
            }
            var values: [Result<CPAQuotaRefreshResult, Error>] = []
            for await value in group { values.append(value) }
            return values
        }

        let requests = await transportA.recordedRequests() + transportB.recordedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/quota/refresh" }.count, 1)
        XCTAssertEqual(results.filter { if case .success = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(
            results.compactMap { result -> CPAQuotaRefreshError? in
                guard case let .failure(error) = result else { return nil }
                return error as? CPAQuotaRefreshError
            },
            [.cooldown(60)]
        )
    }

    func testCooldownIsGlobalAcrossDifferentServiceURLs() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let firstTransport = successfulTransport()
        let secondTransport = successfulTransport()
        let first = makeClient(transport: firstTransport, defaults: defaults, clock: clock)
        let second = CPAQuotaRefreshClient(
            baseURL: URL(string: "https://another-keeper.example")!,
            transport: secondTransport,
            cooldownStore: makeCooldownStore(defaults: defaults),
            currentDate: { clock.now },
            sleep: { _ in }
        )

        _ = try await first.refreshHighestPriorityCodexQuota(password: "test-password")
        do {
            _ = try await second.refreshHighestPriorityCodexQuota(password: "test-password")
            XCTFail("Expected global cooldown across configurations")
        } catch let error as CPAQuotaRefreshError {
            XCTAssertEqual(error, .cooldown(60))
        }
        let secondRequestCount = await secondTransport.requestCount()
        XCTAssertEqual(secondRequestCount, 0)
    }

    func testRedirectResponseIsRejectedWithoutTransportReplay() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
        let defaults = try makeDefaults()
        let transport = ScriptedQuotaTransport { request, _ in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/auth/login"):
                return Self.response(for: request, body: "{}")
            case ("GET", "/api/v1/usage/identities/page"):
                return Self.response(
                    for: request,
                    body: #"{"identities":[{"identity":"auth-codex","type":"codex","provider":"codex","disabled":false}]}"#
                )
            case ("POST", "/api/v1/quota/refresh"):
                return Self.response(for: request, status: 307, body: "")
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let client = makeClient(transport: transport, defaults: defaults, clock: clock)

        do {
            _ = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
            XCTFail("Expected redirect rejection")
        } catch let error as CPAQuotaRefreshError {
            XCTAssertEqual(error, .redirectRejected)
        }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/quota/refresh" }.count, 1)
    }

    func testCompletedTaskRequiresMatchingQuotaIDAndValidRefreshTime() async throws {
        for body in [
            #"{"authIndex":"auth-codex","status":"completed","quota":{"id":"other","quota":[]},"refreshed_at":"2026-08-13T09:59:14+08:00"}"#,
            #"{"authIndex":"auth-codex","status":"completed","quota":{"id":"auth-codex","quota":[]},"refreshed_at":"not-a-date"}"#
        ] {
            let clock = TestClock(Date(timeIntervalSince1970: 1_786_560_000))
            let defaults = try makeDefaults()
            let transport = successfulTransport(completedBody: body)
            let client = makeClient(transport: transport, defaults: defaults, clock: clock)
            do {
                _ = try await client.refreshHighestPriorityCodexQuota(password: "test-password")
                XCTFail("Expected strict completed response validation")
            } catch let error as CPAQuotaRefreshError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    private func successfulTransport(
        completedBody: String = #"{"authIndex":"auth-codex","status":"completed","quota":{"id":"auth-codex","quota":[]},"refreshed_at":"2026-08-13T09:59:14+08:00"}"#
    ) -> ScriptedQuotaTransport {
        ScriptedQuotaTransport { request, _ in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/auth/login"):
                return Self.response(for: request, body: "{}")
            case ("GET", "/api/v1/usage/identities/page"):
                return Self.response(
                    for: request,
                    body: #"{"identities":[{"identity":"auth-codex","type":"codex","provider":"codex","disabled":false}]}"#
                )
            case ("POST", "/api/v1/quota/refresh"):
                return Self.response(
                    for: request,
                    body: #"{"tasks":[{"authIndex":"auth-codex"}],"rejected":[],"accepted":1,"skipped":0,"limit":1}"#
                )
            case ("GET", "/api/v1/quota/refresh/auth-codex"):
                return Self.response(for: request, body: completedBody)
            default:
                throw URLError(.unsupportedURL)
            }
        }
    }

    private func makeClient(
        transport: ScriptedQuotaTransport,
        defaults: UserDefaults,
        clock: TestClock
    ) -> CPAQuotaRefreshClient {
        CPAQuotaRefreshClient(
            baseURL: URL(string: "https://keeper.example")!,
            transport: transport,
            cooldownStore: makeCooldownStore(defaults: defaults),
            currentDate: { clock.now },
            sleep: { _ in }
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "CPAQuotaRefreshTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Cannot create isolated UserDefaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeCooldownStore(defaults: UserDefaults) -> QuotaRefreshCooldownStore {
        QuotaRefreshCooldownStore(defaults: defaults, lockFileURL: nil)
    }

    private static func response(
        for request: URLRequest,
        status: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func requestBody(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(contentsOf: buffer[..<count])
        }
        return data
    }
}

private final class TestClock: @unchecked Sendable {
    let now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private actor DurationRecorder {
    private var values: [Duration] = []

    func record(_ duration: Duration) {
        values.append(duration)
    }

    func recordedDurations() -> [Duration] {
        values
    }
}

private actor ScriptedQuotaTransport: CPAQuotaRefreshTransport {
    typealias Handler = @Sendable (URLRequest, Int) throws -> (HTTPURLResponse, Data)

    private let handler: Handler
    private var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (response, data) = try handler(request, requests.count)
        return (data, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func requestCount() -> Int {
        requests.count
    }
}

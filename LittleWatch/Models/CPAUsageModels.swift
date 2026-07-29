import Foundation

struct CPAUsageOverviewResponse: Decodable, Equatable, Sendable {
    let usage: CPAUsageTotals
    let summary: CPAUsageSummary
    let timezone: String?
}

struct CPAUsageTotals: Decodable, Equatable, Sendable {
    let totalRequests: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRequests = try container.decodeFlexibleIntIfPresent(forKey: .totalRequests)
        totalTokens = try container.decodeFlexibleIntIfPresent(forKey: .totalTokens)
    }
}

struct CPAUsageSummary: Decodable, Equatable, Sendable {
    let tokenCount: Int?
    let totalCost: Double?
    let costAvailable: Bool?
    let rpm: Double?
    let tpm: Double?

    enum CodingKeys: String, CodingKey {
        case tokenCount = "token_count"
        case totalCost = "total_cost"
        case costAvailable = "cost_available"
        case rpm
        case tpm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokenCount = try container.decodeFlexibleIntIfPresent(forKey: .tokenCount)
        totalCost = try container.decodeFlexibleDoubleIfPresent(forKey: .totalCost)
        costAvailable = try container.decodeIfPresent(Bool.self, forKey: .costAvailable)
        rpm = try container.decodeFlexibleDoubleIfPresent(forKey: .rpm)
        tpm = try container.decodeFlexibleDoubleIfPresent(forKey: .tpm)
    }
}

struct CPAUsageRealtimeResponse: Decodable, Equatable, Sendable {
    let window: String
    let timezone: String?
    let bucketSeconds: Int?
    let tokenVelocity: [CPATokenVelocityPoint]
    let requestLevel: [CPARequestLevelPoint]

    enum CodingKeys: String, CodingKey {
        case window
        case timezone
        case bucketSeconds = "bucket_seconds"
        case tokenVelocity = "token_velocity"
        case requestLevel = "request_level"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        window = try container.decodeIfPresent(String.self, forKey: .window) ?? "60m"
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        bucketSeconds = try container.decodeFlexibleIntIfPresent(forKey: .bucketSeconds)
        tokenVelocity = try container.decodeIfPresent([CPATokenVelocityPoint].self, forKey: .tokenVelocity) ?? []
        requestLevel = try container.decodeIfPresent([CPARequestLevelPoint].self, forKey: .requestLevel) ?? []
    }
}

struct CPATokenVelocityPoint: Decodable, Equatable, Sendable {
    let bucket: String?
    let tokensPerMinute: Double?
    let tokens: Int?

    enum CodingKeys: String, CodingKey {
        case bucket
        case tokensPerMinute = "tokens_per_minute"
        case tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket)
        tokensPerMinute = try container.decodeFlexibleDoubleIfPresent(forKey: .tokensPerMinute)
        tokens = try container.decodeFlexibleIntIfPresent(forKey: .tokens)
    }
}

struct CPARequestLevelPoint: Decodable, Equatable, Sendable {
    let bucket: String?
    let requestsPerMinute: Double?
    let requests: Int?

    enum CodingKeys: String, CodingKey {
        case bucket
        case requestsPerMinute = "requests_per_minute"
        case requests
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket)
        requestsPerMinute = try container.decodeFlexibleDoubleIfPresent(forKey: .requestsPerMinute)
        requests = try container.decodeFlexibleIntIfPresent(forKey: .requests)
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }
}

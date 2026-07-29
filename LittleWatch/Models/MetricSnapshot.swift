import Foundation

struct MetricSnapshot: Equatable, Sendable {
    let costUSD: Double
    let tokenCount: Int
    let updatedAt: Date
    let totalRequests: Int?
    let tokensPerMinute: Double?
    let requestsPerMinute: Double?

    init(
        costUSD: Double,
        tokenCount: Int,
        updatedAt: Date,
        totalRequests: Int? = nil,
        tokensPerMinute: Double? = nil,
        requestsPerMinute: Double? = nil
    ) {
        self.costUSD = costUSD
        self.tokenCount = tokenCount
        self.updatedAt = updatedAt
        self.totalRequests = totalRequests
        self.tokensPerMinute = tokensPerMinute
        self.requestsPerMinute = requestsPerMinute
    }
}

enum RefreshState: Equatable {
    case idle
    case refreshing
    case failed(String)
}

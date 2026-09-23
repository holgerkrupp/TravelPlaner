import Foundation

enum VoteValue: String, Codable, Sendable { case worthVisiting, notWorthVisiting }
enum VoteVerificationType: String, Codable, Sendable { case currentProximity, observedVisit, activeTrip }

struct PlaceVote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let placeID: UUID
    var value: VoteValue
    var verification: VoteVerificationType
    var coarseVisitMonth: Date?
    var updatedAt: Date
}

nonisolated struct VoteAggregate: Codable, Equatable, Sendable {
    let positiveCount: Int
    let negativeCount: Int
    let confidenceScore: Double
    let isInformative: Bool

    var totalCount: Int { positiveCount + negativeCount }
}

enum VoteAggregator {
    nonisolated static func aggregate(_ votes: [PlaceVote], minimumInformativeVotes: Int = 3) -> VoteAggregate {
        let positive = votes.filter { $0.value == .worthVisiting }.count
        let negative = votes.count - positive
        let total = positive + negative
        // A weakly informative Beta(1, 1) prior keeps small samples neutral.
        let posterior = Double(positive + 1) / Double(total + 2)
        let confidence = total == 0 ? 0.5 : posterior
        return VoteAggregate(positiveCount: positive, negativeCount: negative, confidenceScore: confidence, isInformative: total >= minimumInformativeVotes)
    }
}

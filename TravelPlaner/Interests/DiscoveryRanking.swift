import Foundation

struct RankingInputs: Equatable, Sendable {
    var baseNotability: Double
    var uniqueness: Double
    var sourceConfidence: Double
    var matchingInterestCount: Int
    var selectedInterestCount: Int
    var routeRelevance: Double
    var voteSignal: Double?
    var detourPenalty: Double
    var fatiguePenalty: Double

    init(
        baseNotability: Double,
        uniqueness: Double = 0.5,
        sourceConfidence: Double = 0.5,
        matchingInterestCount: Int = 0,
        selectedInterestCount: Int = 0,
        routeRelevance: Double = 0.5,
        voteSignal: Double? = nil,
        detourPenalty: Double = 0,
        fatiguePenalty: Double = 0
    ) {
        self.baseNotability = baseNotability
        self.uniqueness = uniqueness
        self.sourceConfidence = sourceConfidence
        self.matchingInterestCount = matchingInterestCount
        self.selectedInterestCount = selectedInterestCount
        self.routeRelevance = routeRelevance
        self.voteSignal = voteSignal
        self.detourPenalty = detourPenalty
        self.fatiguePenalty = fatiguePenalty
    }
}

struct RankingWeights: Equatable, Sendable {
    var baseNotability = 0.24
    var uniqueness = 0.20
    var sourceConfidence = 0.12
    var interestMatch = 0.16
    var routeRelevance = 0.12
    var voteSignal = 0.10
    var detourPenalty = 0.04
    var fatiguePenalty = 0.02
}

struct DiscoveryScore: Equatable, Sendable, Comparable {
    let total: Double
    let components: [String: Double]
    let reasons: [String]

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.total < rhs.total }
}

struct DiscoveryRanker: Sendable {
    let weights: RankingWeights

    init(weights: RankingWeights = RankingWeights()) { self.weights = weights }

    func score(_ input: RankingInputs) -> DiscoveryScore {
        let interest = input.selectedInterestCount == 0
            ? 0.5
            : min(1, Double(input.matchingInterestCount) / Double(input.selectedInterestCount))
        let vote = input.voteSignal ?? 0.5
        let components = [
            "notability": clamp(input.baseNotability),
            "uniqueness": clamp(input.uniqueness),
            "sourceConfidence": clamp(input.sourceConfidence),
            "interestMatch": clamp(interest),
            "routeRelevance": clamp(input.routeRelevance),
            "voteSignal": clamp(vote),
            "detourPenalty": clamp(input.detourPenalty),
            "fatiguePenalty": clamp(input.fatiguePenalty)
        ]
        let positive = weights.baseNotability * components["notability"]!
            + weights.uniqueness * components["uniqueness"]!
            + weights.sourceConfidence * components["sourceConfidence"]!
            + weights.interestMatch * components["interestMatch"]!
            + weights.routeRelevance * components["routeRelevance"]!
            + weights.voteSignal * components["voteSignal"]!
        let total = max(0, positive - weights.detourPenalty * components["detourPenalty"]!
            - weights.fatiguePenalty * components["fatiguePenalty"]!)
        var reasons: [String] = []
        if components["uniqueness"]! >= 0.7 { reasons.append("Unusually distinctive") }
        if interest > 0.5 { reasons.append("Matches your interests") }
        if input.routeRelevance >= 0.7 { reasons.append("Relevant to your route") }
        if input.voteSignal == nil { reasons.append("No community votes yet") }
        return DiscoveryScore(total: total, components: components, reasons: reasons)
    }

    func rank(_ places: [(Place, RankingInputs)]) -> [(Place, DiscoveryScore)] {
        places.map { ($0.0, score($0.1)) }.sorted {
            if $0.1.total != $1.1.total { return $0.1.total > $1.1.total }
            return $0.0.id.uuidString < $1.0.id.uuidString
        }
    }

    private func clamp(_ value: Double) -> Double { min(1, max(0, value.isFinite ? value : 0)) }
}

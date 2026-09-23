import Foundation

struct PlaceCandidate: Equatable, Sendable {
    let place: Place
    let discoveredAt: Date
    let canRepublish: Bool
}

struct CoveragePolicy: Equatable, Sendable {
    var minimumPlaces = 3
    var freshness: TimeInterval = 7 * 24 * 60 * 60
}

struct CoverageEvaluator: Sendable {
    let policy: CoveragePolicy

    func isSufficient(_ places: [Place], checkedAt: Date = .now, lastSuccessfulCheck: Date? = nil) -> Bool {
        guard places.count >= policy.minimumPlaces else { return false }
        if let lastSuccessfulCheck { return checkedAt.timeIntervalSince(lastSuccessfulCheck) <= policy.freshness }
        return true
    }
}

protocol PlaceSourceAdapter: Sendable {
    var source: PlaceSource { get }
    func discover(in region: CoverageRegion) async throws -> [PlaceCandidate]
}

struct FixturePlaceSourceAdapter: PlaceSourceAdapter {
    let source: PlaceSource = .wikidata
    let fixtures: [Place]

    func discover(in region: CoverageRegion) async throws -> [PlaceCandidate] {
        try Task.checkCancellation()
        return fixtures.map { PlaceCandidate(place: $0, discoveredAt: .now, canRepublish: true) }
    }
}

struct DiscoveryPipeline: POIDiscoveryService {
    let cloudKit: any CloudKitService
    let adapters: [any PlaceSourceAdapter]
    let evaluator: CoverageEvaluator

    func discover(for request: DiscoveryRequest) async throws -> [Place] {
        let region = CoverageRegion(center: request.center, radius: request.radius)
        let shared = (try? await cloudKit.fetchPlaces(in: region)) ?? []
        if evaluator.isSufficient(shared) { return PlaceDeduplicator.unique(shared) }
        var candidates = shared
        var discoveredCandidates: [PlaceCandidate] = []
        for adapter in adapters {
            try Task.checkCancellation()
            let results = try await adapter.discover(in: region)
            discoveredCandidates.append(contentsOf: results)
            candidates.append(contentsOf: results.map(\.place))
        }
        let publishable = discoveredCandidates.filter(\.canRepublish).map(\.place)
        if !publishable.isEmpty { try? await cloudKit.publish(publishable) }
        return PlaceDeduplicator.unique(candidates)
    }
}

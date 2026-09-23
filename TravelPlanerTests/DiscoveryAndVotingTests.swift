import CoreLocation
import XCTest
@testable import TravelPlaner

@MainActor
final class DiscoveryAndVotingTests: XCTestCase {
    private func place(notability: Double, interests: Set<PlaceInterest> = []) throws -> Place {
        try Place(
            name: "Test place",
            coordinate: try GeoCoordinate(latitude: 48, longitude: 11),
            category: .nature,
            interests: interests,
            editorialReason: "A fixture discovery.",
            sources: [try PlaceSourceReference(source: .wikidata, externalID: UUID().uuidString)],
            baseNotability: notability
        )
    }

    func testRankingIsExplainableAndDoesNotFilterNonMatchingPlaces() throws {
        let ranker = DiscoveryRanker()
        let unique = try place(notability: 0.35)
        let generic = try place(notability: 0.95)
        let result = ranker.rank([
            (unique, RankingInputs(baseNotability: unique.baseNotability, uniqueness: 1, routeRelevance: 1)),
            (generic, RankingInputs(baseNotability: generic.baseNotability, uniqueness: 0.1, routeRelevance: 0.2))
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.0.id, unique.id)
        XCTAssertFalse(result.first?.1.reasons.isEmpty ?? true)
    }

    func testVisitEligibilityRejectsStaleOrDistantEvidence() throws {
        let place = try place(notability: 0.5)
        let evaluator = VisitEligibilityEvaluator(policy: VisitEligibilityPolicy(maximumAccuracyMeters: 50, maximumAge: 60, defaultRadiusMeters: 100))
        let now = Date()
        let valid = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 48, longitude: 11), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: now)
        XCTAssertNotNil(evaluator.evaluate(place: place, location: valid, now: now))
        let stale = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 48, longitude: 11), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: now.addingTimeInterval(-61))
        XCTAssertNil(evaluator.evaluate(place: place, location: stale, now: now))
    }

    func testVoteAggregateUsesNeutralPriorAndMinimumSampleThreshold() {
        let aggregate = VoteAggregator.aggregate([
            PlaceVote(id: UUID(), placeID: UUID(), value: .worthVisiting, verification: .currentProximity, coarseVisitMonth: nil, updatedAt: .now)
        ])
        XCTAssertEqual(aggregate.confidenceScore, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertFalse(aggregate.isInformative)
    }
}

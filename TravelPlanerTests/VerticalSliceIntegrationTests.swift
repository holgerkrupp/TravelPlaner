import CoreLocation
import XCTest
@testable import TravelPlaner

private struct VerticalSliceCloud: CloudKitService {
    func fetchPlaces(in region: CoverageRegion) async throws -> [Place] { [] }
    func publish(_ places: [Place]) async throws { }
}

private struct VerticalSliceRoute: RouteService {
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> Route {
        Route(distance: 2_000, expectedTravelTime: 120)
    }
}

@MainActor
final class VerticalSliceIntegrationTests: XCTestCase {
    func testDiscoveryToVoteVerticalSlice() async throws {
        let place = try Place(
            name: "Vertical slice fixture",
            coordinate: try GeoCoordinate(latitude: 48.02, longitude: 11.02),
            category: .unusual,
            interests: [.unusual],
            editorialReason: "A deliberately limited, source-backed fixture.",
            sources: [try PlaceSourceReference(source: .wikidata, externalID: "Q-vertical")],
            baseNotability: 0.8
        )
        let pipeline = DiscoveryPipeline(
            cloudKit: VerticalSliceCloud(),
            adapters: [FixturePlaceSourceAdapter(fixtures: [place])],
            evaluator: CoverageEvaluator(policy: CoveragePolicy(minimumPlaces: 3))
        )
        let discovered = try await pipeline.discover(for: DiscoveryRequest(center: CLLocationCoordinate2D(latitude: 48, longitude: 11), radius: 10_000))
        let ranked = DiscoveryRanker().rank(discovered.map { ($0, RankingInputs(baseNotability: $0.baseNotability, matchingInterestCount: 1, selectedInterestCount: 1)) })
        let detour = try await VerticalSliceRoute().calculateRoute(
            from: CLLocationCoordinate2D(latitude: 48, longitude: 11),
            to: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        )
        let now = Date()
        let evidence = CLLocation(coordinate: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: now)
        let eligibility = VisitEligibilityEvaluator(policy: VisitEligibilityPolicy()).evaluate(place: place, location: evidence, now: now)
        let aggregate = VoteAggregator.aggregate([PlaceVote(id: UUID(), placeID: place.id, value: .worthVisiting, verification: .currentProximity, updatedAt: now)])

        XCTAssertEqual(ranked.first?.0.id, place.id)
        XCTAssertEqual(detour.expectedTravelTime, 120)
        XCTAssertEqual(eligibility?.placeID, place.id)
        XCTAssertFalse(aggregate.isInformative)
    }
}

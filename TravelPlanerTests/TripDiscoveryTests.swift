import CoreLocation
import XCTest
@testable import TravelPlaner

private struct EmptyCloudService: CloudKitService {
    func fetchPlaces(in region: CoverageRegion) async throws -> [Place] { [] }
    func publish(_ places: [Place]) async throws { }
}

private struct FixedRouteService: RouteService {
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> Route {
        Route(distance: 1_000, expectedTravelTime: 60)
    }
}

@MainActor
final class TripDiscoveryTests: XCTestCase {
    func testTripDiscoveryUsesFixtureAdapterAndRanksCorridorCandidates() async throws {
        let place = try Place(
            name: "Corridor discovery",
            coordinate: try GeoCoordinate(latitude: 48.05, longitude: 11.05),
            category: .unusual,
            editorialReason: "A useful fixture candidate.",
            sources: [try PlaceSourceReference(source: .wikidata, externalID: "Q-trip-test")],
            baseNotability: 0.8
        )
        let pipeline = DiscoveryPipeline(
            cloudKit: EmptyCloudService(),
            adapters: [FixturePlaceSourceAdapter(fixtures: [place])],
            evaluator: CoverageEvaluator(policy: CoveragePolicy(minimumPlaces: 3))
        )
        let stops = [
            TripStop(name: "Start", coordinate: try GeoCoordinate(latitude: 48, longitude: 11), order: 0),
            TripStop(name: "End", coordinate: try GeoCoordinate(latitude: 48.1, longitude: 11.1), order: 1)
        ]
        let trip = Trip(name: "Fixture trip", stops: stops)
        let coordinator = TripDiscoveryCoordinator(discovery: pipeline, route: FixedRouteService(), ranker: DiscoveryRanker())
        let results = try await coordinator.discover(for: trip)

        XCTAssertEqual(results.map(\.place.id), [place.id])
        XCTAssertEqual(results.first?.approximateDetour?.expectedTravelTime, 120)
    }
}

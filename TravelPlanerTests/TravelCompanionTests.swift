import XCTest
@testable import TravelPlaner

@MainActor
final class TravelCompanionTests: XCTestCase {
    func testTravelCompanionEnforcesDailyHintCap() async throws {
        let companion = TravelCompanion(minimumInterval: 0, maximumHintsPerDay: 2)
        let score = DiscoveryScore(total: 0.9, components: [:], reasons: [])
        let first = try place("First")
        let second = try place("Second")
        let third = try place("Third")
        let now = Date(timeIntervalSince1970: 100_000)

        let firstHint = await companion.eligibleHint(for: first, score: score, now: now)
        let secondHint = await companion.eligibleHint(for: second, score: score, now: now.addingTimeInterval(1))
        let thirdHint = await companion.eligibleHint(for: third, score: score, now: now.addingTimeInterval(2))
        XCTAssertNotNil(firstHint)
        XCTAssertNotNil(secondHint)
        XCTAssertNil(thirdHint)
    }

    private func place(_ name: String) throws -> Place {
        try Place(name: name, coordinate: try GeoCoordinate(latitude: 48, longitude: 11), category: .unusual, editorialReason: "Fixture.", sources: [try PlaceSourceReference(source: .wikidata, externalID: name)])
    }
}

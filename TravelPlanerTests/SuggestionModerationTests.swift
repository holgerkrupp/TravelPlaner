import XCTest
@testable import TravelPlaner

@MainActor
final class SuggestionModerationTests: XCTestCase {
    func testReviewFlagsNearbySuggestionWithoutPromotingIt() throws {
        let source = try PlaceSourceReference(source: .wikidata, externalID: "Q-review")
        let existing = try Place(name: "Old Mill", coordinate: try GeoCoordinate(latitude: 48, longitude: 11), category: .industrialHeritage, editorialReason: "A source-backed mill.", sources: [source])
        let suggestion = try PlaceSuggestion(name: "Old Mill", coordinate: try GeoCoordinate(latitude: 48.0005, longitude: 11), category: .industrialHeritage, reason: "A local discovery.")
        let review = SuggestionModerationEngine.review(suggestion, against: [existing])
        XCTAssertEqual(review.likelyDuplicateIDs, [existing.id])
        XCTAssertEqual(suggestion.status, .pending)
    }

    func testApprovalRequiresExplicitDeveloperProvenance() throws {
        let suggestion = try PlaceSuggestion(name: "Approved", coordinate: try GeoCoordinate(latitude: 48, longitude: 11), category: .unusual, reason: "Verified by a developer.")
        let source = try PlaceSourceReference(source: .officialTourism, externalID: "official-1")
        let place = try SuggestionModerationEngine.approve(suggestion, source: source)
        XCTAssertEqual(place.id, suggestion.id)
        XCTAssertEqual(place.sources.first?.canonicalKey, "officialTourism:official-1")
    }
}

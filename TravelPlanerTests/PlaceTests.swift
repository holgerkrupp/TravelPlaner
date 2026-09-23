import XCTest
@testable import TravelPlaner

final class PlaceTests: XCTestCase {
    private let coordinate = try! GeoCoordinate(latitude: 25.6872, longitude: -80.3046)
    private let source = try! PlaceSourceReference(
        source: .wikidata,
        externalID: "Q12345",
        sourceURL: URL(string: "https://www.wikidata.org/wiki/Q12345"),
        license: "CC0"
    )

    func testSourceReferenceUsesStableCanonicalKey() {
        XCTAssertEqual(source.canonicalKey, "wikidata:Q12345")
    }

    func testPlaceRequiresProvenanceAndNormalizesDisplayText() throws {
        let place = try Place(
            name: "  Coral Castle  ",
            coordinate: coordinate,
            category: .architecture,
            editorialReason: "  An unusual hand-built landmark. ",
            sources: [source]
        )

        XCTAssertEqual(place.name, "Coral Castle")
        XCTAssertEqual(place.editorialReason, "An unusual hand-built landmark.")
        XCTAssertEqual(place.canonicalSourceKeys, ["wikidata:Q12345"])
        XCTAssertThrowsError(try Place(
            name: "No source",
            coordinate: coordinate,
            category: .other,
            editorialReason: "A reason",
            sources: []
        )) { error in
            XCTAssertEqual(error as? Place.ValidationError, .missingProvenance)
        }
    }

    func testDeduplicatorUsesSourceIdentityNotNameOrArrayPosition() throws {
        let duplicate = try Place(
            name: "Same place, translated",
            coordinate: coordinate,
            category: .architecture,
            editorialReason: "The same source-backed discovery.",
            sources: [source]
        )
        let distinct = try Place(
            name: "Another place",
            coordinate: coordinate,
            category: .architecture,
            editorialReason: "A separate source-backed discovery.",
            sources: [try PlaceSourceReference(source: .openStreetMap, externalID: "way:42")]
        )

        XCTAssertEqual(PlaceDeduplicator.unique([duplicate, distinct, duplicate]).map(\.name), ["Same place, translated", "Another place"])
    }

    func testInvalidCoordinatesAreRejected() {
        XCTAssertThrowsError(try GeoCoordinate(latitude: 91, longitude: 0))
        XCTAssertThrowsError(try GeoCoordinate(latitude: 0, longitude: 181))
    }
}

import CloudKit
import CoreLocation
import SwiftData
import XCTest
@testable import TravelPlaner

@MainActor
final class PersistenceAndCloudKitTests: XCTestCase {
    func testTripStoreRoundTripsStopsAndUpdates() throws {
        let container = try TravelPlanerSchema.container(inMemory: true)
        let store = SwiftDataTripStore(context: ModelContext(container))
        let tripID = UUID()
        let stop = TripStop(
            name: "Marble Caves",
            coordinate: try GeoCoordinate(latitude: -46.65, longitude: -72.63),
            order: 0
        )
        let trip = Trip(id: tripID, name: "Patagonia", destinations: ["Chile"], stops: [stop])

        store.add(trip)
        XCTAssertEqual(store.trips.first?.stops, [stop])

        var updated = trip
        updated.name = "Patagonia road trip"
        updated.stops = []
        store.update(updated)
        XCTAssertEqual(store.trips.first?.name, "Patagonia road trip")
        XCTAssertEqual(store.trips.first?.stops, [])

        store.remove(id: tripID)
        XCTAssertTrue(store.trips.isEmpty)
    }

    func testCloudKitPlaceMappingPreservesStableIdentityAndProvenance() throws {
        let source = try PlaceSourceReference(
            source: .wikidata,
            externalID: "Q12345",
            sourceURL: URL(string: "https://www.wikidata.org/entity/Q12345"),
            license: "CC0",
            attribution: "Wikidata"
        )
        let place = try Place(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "Taylor Glacier",
            coordinate: GeoCoordinate(latitude: -78.18, longitude: 163.25),
            category: .geology,
            interests: [.nature, .science],
            kind: .remoteDestination,
            editorialReason: "A rare visible blood-red waterfall.",
            sources: [source]
        )

        let record = try CloudKitPlaceRecordMapper.makeRecord(from: place)
        let restored = try CloudKitPlaceRecordMapper.makePlace(from: record)

        XCTAssertEqual(record.recordID, CloudKitPlaceRecordMapper.recordID(for: place))
        XCTAssertEqual(restored.id, place.id)
        XCTAssertEqual(restored.sources.first?.canonicalKey, "wikidata:Q12345")
        XCTAssertEqual(restored.sources.first?.license, "CC0")
        XCTAssertEqual(restored.coordinate.latitude, place.coordinate.latitude, accuracy: 0.000001)
    }

    func testPlaceSnapshotSurvivesStoreReload() throws {
        let container = try TravelPlanerSchema.container(inMemory: true)
        let context = ModelContext(container)
        let store = SwiftDataPlaceSnapshotStore(context: context)
        let source = try PlaceSourceReference(source: .wikidata, externalID: "Q-cache")
        let place = try Place(name: "Sequoia National Park", coordinate: try GeoCoordinate(latitude: 36.5, longitude: -118.5), category: .park, editorialReason: "Giant trees.", sources: [source])

        store.store([place], context: "nearby")
        let reloaded = SwiftDataPlaceSnapshotStore(context: ModelContext(container)).load(context: "nearby")

        XCTAssertEqual(reloaded?.places, [place])
    }

    func testVoteAggregateSnapshotSurvivesStoreReload() throws {
        let container = try TravelPlanerSchema.container(inMemory: true)
        let placeID = UUID()
        let aggregate = VoteAggregate(positiveCount: 2, negativeCount: 1, confidenceScore: 0.6, isInformative: true)
        SwiftDataVoteAggregateStore(context: ModelContext(container)).store(aggregate, for: placeID)

        let reloaded = SwiftDataVoteAggregateStore(context: ModelContext(container)).load(for: placeID)
        XCTAssertEqual(reloaded?.aggregate, aggregate)
    }
}

import CloudKit
import CoreLocation
import SwiftData
import XCTest
@testable import TravelPlaner

private struct SinglePlaceCloud: CloudKitService {
    let place: Place
    func fetchPlaces(in region: CoverageRegion) async throws -> [Place] { [place] }
    func fetchPlace(stableID: UUID) async throws -> Place? { place.id == stableID ? place : nil }
    func publish(_ places: [Place]) async throws { }
}

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
            attribution: "Wikidata",
            sourceUpdatedAt: Date(timeIntervalSince1970: 1234),
            discoveryVersion: "fixture-v2"
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
        XCTAssertEqual(restored.sources.first?.sourceUpdatedAt, Date(timeIntervalSince1970: 1234))
        XCTAssertEqual(restored.sources.first?.discoveryVersion, "fixture-v2")
        XCTAssertEqual(restored.coordinate.latitude, place.coordinate.latitude, accuracy: 0.000001)
    }

    func testCloudKitRecordIdentityUsesTheSameCanonicalSourceThatIsStored() throws {
        let first = try PlaceSourceReference(source: .wikidata, externalID: "Q-z")
        let second = try PlaceSourceReference(source: .openStreetMap, externalID: "node:1")
        let place = try Place(name: "Multi-source", coordinate: try GeoCoordinate(latitude: 48, longitude: 11), category: .other, editorialReason: "Fixture.", sources: [first, second])

        let record = try CloudKitPlaceRecordMapper.makeRecord(from: place)
        XCTAssertEqual(record.recordID, CloudKitPlaceRecordMapper.recordID(for: place))
        XCTAssertEqual(record["source"] as? String, "openStreetMap")
        XCTAssertEqual(record["externalID"] as? String, "node:1")
    }

    func testCloudKitPlaceMappingPreservesAllSourceProvenance() throws {
        let wikidata = try PlaceSourceReference(source: .wikidata, externalID: "Q-multi")
        let osm = try PlaceSourceReference(
            source: .openStreetMap,
            externalID: "way:multi",
            license: "ODbL 1.0",
            attribution: "OpenStreetMap contributors"
        )
        let place = try Place(
            name: "Multi-source fixture",
            coordinate: try GeoCoordinate(latitude: 48, longitude: 11),
            category: .unusual,
            editorialReason: "Provenance fixture.",
            sources: [wikidata, osm]
        )

        let restored = try CloudKitPlaceRecordMapper.makePlace(from: CloudKitPlaceRecordMapper.makeRecord(from: place))

        XCTAssertEqual(Set(restored.sources.map(\.canonicalKey)), Set(place.sources.map(\.canonicalKey)))
        XCTAssertEqual(restored.sources.first(where: { $0.source == .openStreetMap })?.license, "ODbL 1.0")
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

    func testPlaceSnapshotEvictionUsesDefinedRetentionWindow() throws {
        let container = try TravelPlanerSchema.container(inMemory: true)
        let context = ModelContext(container)
        let store = SwiftDataPlaceSnapshotStore(context: context)
        let source = try PlaceSourceReference(source: .wikidata, externalID: "Q-old-cache")
        let place = try Place(name: "Old cache", coordinate: try GeoCoordinate(latitude: 1, longitude: 1), category: .other, editorialReason: "Fixture.", sources: [source])
        let now = Date(timeIntervalSince1970: 10_000_000)
        store.store([place], context: "old", now: now.addingTimeInterval(-SwiftDataPlaceSnapshotStore.retention - 1))

        XCTAssertEqual(store.evictExpired(now: now), 1)
        XCTAssertNil(store.load(context: "old", now: now))
    }

    func testVoteAggregateSnapshotSurvivesStoreReload() throws {
        let container = try TravelPlanerSchema.container(inMemory: true)
        let placeID = UUID()
        let aggregate = VoteAggregate(positiveCount: 2, negativeCount: 1, confidenceScore: 0.6, isInformative: true)
        SwiftDataVoteAggregateStore(context: ModelContext(container)).store(aggregate, for: placeID)

        let reloaded = SwiftDataVoteAggregateStore(context: ModelContext(container)).load(for: placeID)
        XCTAssertEqual(reloaded?.aggregate, aggregate)
    }

    func testVoteIdentitySupportsChangesWithoutDuplicateAccountPlaceRecords() {
        let placeID = UUID()
        let first = CloudKitVoteService.recordID(userKey: "account-A", placeID: placeID)
        let changedValueUsesSameRecord = CloudKitVoteService.recordID(userKey: "account-A", placeID: placeID)
        let otherAccount = CloudKitVoteService.recordID(userKey: "account-B", placeID: placeID)

        XCTAssertEqual(first, changedValueUsesSameRecord)
        XCTAssertNotEqual(first, otherAccount)
    }

    func testPlaceRepositoryFetchesByStableTravelPlanerID() async throws {
        let source = try PlaceSourceReference(source: .wikidata, externalID: "Q-direct")
        let place = try Place(id: UUID(), name: "Direct lookup", coordinate: try GeoCoordinate(latitude: 48, longitude: 11), category: .unusual, editorialReason: "Fixture.", sources: [source])
        let repository = PlaceRepository(service: SinglePlaceCloud(place: place))
        let region = CoverageRegion(center: CLLocationCoordinate2D(latitude: 48, longitude: 11), radius: 1000)

        _ = try await repository.places(in: region)
        let found = try await repository.place(id: place.id)
        XCTAssertEqual(found?.id, place.id)
    }

    func testSavedPlaceCanBeToggledAndRestored() throws {
        let container = try TravelPlanerSchema.container(inMemory: true)
        let context = ModelContext(container)
        let source = try PlaceSourceReference(source: .wikidata, externalID: "Q-saved")
        let place = try Place(name: "Saved fixture", coordinate: try GeoCoordinate(latitude: 48, longitude: 11), category: .unusual, editorialReason: "Fixture.", sources: [source])
        let store = SwiftDataSavedPlaceStore(context: context)

        XCTAssertTrue(store.toggle(place))
        XCTAssertTrue(store.contains(place.id))
        XCTAssertEqual(store.all().first?.id, place.id)
        XCTAssertFalse(store.toggle(place))
        XCTAssertFalse(store.contains(place.id))
    }

    func testVisitEligibilityEvidenceIsStoredOnlyUntilItsExpiry() throws {
        let container = try TravelPlanerSchema.container(inMemory: true)
        let store = SwiftDataVisitEligibilityStore(context: ModelContext(container))
        let placeID = UUID()
        let observedAt = Date(timeIntervalSince1970: 50_000)
        let evidence = VisitEvidence(placeID: placeID, observedAt: observedAt, distanceMeters: 25, horizontalAccuracyMeters: 10)

        store.record(evidence, expiresAt: observedAt.addingTimeInterval(60))
        XCTAssertTrue(store.isEligible(placeID: placeID, now: observedAt.addingTimeInterval(30)))
        XCTAssertEqual(store.observedAt(for: placeID, now: observedAt.addingTimeInterval(30)), observedAt)
        XCTAssertFalse(store.isEligible(placeID: placeID, now: observedAt.addingTimeInterval(61)))
    }

    func testSuggestionStatusIsKeptLocallyUntilModeration() throws {
        let container = try TravelPlanerSchema.container(inMemory: true)
        let store = SwiftDataSuggestionStore(context: ModelContext(container))
        let suggestion = try PlaceSuggestion(name: "Local suggestion", coordinate: try GeoCoordinate(latitude: 48, longitude: 11), category: .unusual, reason: "Fixture.")

        store.record(suggestion)
        XCTAssertEqual(store.all().first?.status, .pending)
    }
}

import Foundation
import SwiftData
import Combine

@Model final class PersistedTrip {
    @Attribute(.unique) var id: UUID
    var name: String
    var startDate: Date?
    var endDate: Date?
    var destinations: [String]
    var stopsData: Data

    init(_ trip: Trip) {
        id = trip.id
        name = trip.name
        startDate = trip.startDate
        endDate = trip.endDate
        destinations = trip.destinations
        stopsData = (try? JSONEncoder().encode(trip.stops)) ?? Data()
    }

    var stops: [TripStop] {
        get { (try? JSONDecoder().decode([TripStop].self, from: stopsData)) ?? [] }
        set { stopsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var value: Trip { Trip(id: id, name: name, startDate: startDate, endDate: endDate, destinations: destinations, stops: stops) }
}

@Model final class PersistedInterestSelection {
    @Attribute(.unique) var id: String
    var values: [String]
    init(values: Set<PlaceInterest> = []) {
        id = "current"
        self.values = values.map(\.rawValue).sorted()
    }
    var interests: Set<PlaceInterest> { Set(values.compactMap(PlaceInterest.init(rawValue:))) }
}

@Model final class PersistedVisitEligibility {
    @Attribute(.unique) var id: String
    var placeID: UUID
    var observedAt: Date
    var evidence: String
    var expiresAt: Date

    init(placeID: UUID, observedAt: Date, evidence: String, expiresAt: Date) {
        id = placeID.uuidString
        self.placeID = placeID
        self.observedAt = observedAt
        self.evidence = evidence
        self.expiresAt = expiresAt
    }
}

@Model final class PersistedPlaceSnapshot {
    @Attribute(.unique) var cacheKey: String
    var placesData: Data
    var cachedAt: Date

    init(places: [Place], context: String, cachedAt: Date = .now) {
        cacheKey = context
        placesData = (try? JSONEncoder().encode(places)) ?? Data()
        self.cachedAt = cachedAt
    }

    var places: [Place] {
        (try? JSONDecoder().decode([Place].self, from: placesData)) ?? []
    }
}

@Model final class PersistedVoteAggregateSnapshot {
    @Attribute(.unique) var placeID: UUID
    var aggregateData: Data
    var updatedAt: Date

    init(placeID: UUID, aggregate: VoteAggregate, updatedAt: Date = .now) {
        self.placeID = placeID
        aggregateData = (try? JSONEncoder().encode(aggregate)) ?? Data()
        self.updatedAt = updatedAt
    }

    var aggregate: VoteAggregate? { try? JSONDecoder().decode(VoteAggregate.self, from: aggregateData) }
}

@Model final class PersistedSavedPlace {
    @Attribute(.unique) var placeID: UUID
    var placeData: Data
    var savedAt: Date

    init(place: Place, savedAt: Date = .now) {
        placeID = place.id
        placeData = (try? JSONEncoder().encode(place)) ?? Data()
        self.savedAt = savedAt
    }

    var place: Place? { try? JSONDecoder().decode(Place.self, from: placeData) }
}

enum TravelPlanerSchema {
    static let models: [any PersistentModel.Type] = [
        PersistedTrip.self,
        PersistedInterestSelection.self,
        PersistedVisitEligibility.self,
        PersistedPlaceSnapshot.self,
        PersistedVoteAggregateSnapshot.self,
        PersistedSavedPlace.self
    ]

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(models), configurations: configuration)
    }
}

@MainActor
final class SwiftDataPlaceSnapshotStore {
    static let retention: TimeInterval = 30 * 24 * 60 * 60
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func store(_ places: [Place], context key: String, now: Date = .now) {
        evictExpired(now: now)
        let existing = (try? context.fetch(FetchDescriptor<PersistedPlaceSnapshot>()))?.first { $0.cacheKey == key }
        if let existing {
            existing.placesData = (try? JSONEncoder().encode(PlaceDeduplicator.unique(places))) ?? Data()
            existing.cachedAt = now
        } else {
            context.insert(PersistedPlaceSnapshot(places: places, context: key, cachedAt: now))
        }
        try? context.save()
    }

    func load(context key: String, now: Date = .now) -> CachedPlaceSet? {
        evictExpired(now: now)
        guard let stored = (try? context.fetch(FetchDescriptor<PersistedPlaceSnapshot>()))?.first(where: { $0.cacheKey == key }) else { return nil }
        return CachedPlaceSet(places: stored.places, cachedAt: stored.cachedAt, context: key)
    }

    @discardableResult
    func evictExpired(now: Date = .now) -> Int {
        let cutoff = now.addingTimeInterval(-Self.retention)
        let expired = (try? context.fetch(FetchDescriptor<PersistedPlaceSnapshot>()))?.filter { $0.cachedAt < cutoff } ?? []
        expired.forEach(context.delete)
        if !expired.isEmpty { try? context.save() }
        return expired.count
    }
}

struct CachedVoteAggregate: Equatable, Sendable {
    let aggregate: VoteAggregate
    let updatedAt: Date
}

@MainActor
final class SwiftDataVoteAggregateStore {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func store(_ aggregate: VoteAggregate, for placeID: UUID, now: Date = .now) {
        let existing = (try? context.fetch(FetchDescriptor<PersistedVoteAggregateSnapshot>()))?.first { $0.placeID == placeID }
        if let existing {
            existing.aggregateData = (try? JSONEncoder().encode(aggregate)) ?? Data()
            existing.updatedAt = now
        } else {
            context.insert(PersistedVoteAggregateSnapshot(placeID: placeID, aggregate: aggregate, updatedAt: now))
        }
        try? context.save()
    }

    func load(for placeID: UUID) -> CachedVoteAggregate? {
        guard let stored = (try? context.fetch(FetchDescriptor<PersistedVoteAggregateSnapshot>()))?.first(where: { $0.placeID == placeID }),
              let aggregate = stored.aggregate else { return nil }
        return CachedVoteAggregate(aggregate: aggregate, updatedAt: stored.updatedAt)
    }
}

@MainActor
final class SwiftDataSavedPlaceStore {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func contains(_ placeID: UUID) -> Bool {
        (try? context.fetch(FetchDescriptor<PersistedSavedPlace>()))?.contains { $0.placeID == placeID } ?? false
    }

    func toggle(_ place: Place, now: Date = .now) -> Bool {
        if let saved = (try? context.fetch(FetchDescriptor<PersistedSavedPlace>()))?.first(where: { $0.placeID == place.id }) {
            context.delete(saved)
            try? context.save()
            return false
        }
        context.insert(PersistedSavedPlace(place: place, savedAt: now))
        try? context.save()
        return true
    }

    func all() -> [Place] {
        (try? context.fetch(FetchDescriptor<PersistedSavedPlace>()))?.compactMap(\.place) ?? []
    }
}

@MainActor
final class SwiftDataVisitEligibilityStore {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func record(_ evidence: VisitEvidence, expiresAt: Date) {
        let existing = (try? context.fetch(FetchDescriptor<PersistedVisitEligibility>()))?.first { $0.placeID == evidence.placeID }
        if let existing {
            existing.observedAt = evidence.observedAt
            existing.evidence = "distance=\(evidence.distanceMeters),accuracy=\(evidence.horizontalAccuracyMeters)"
            existing.expiresAt = expiresAt
        } else {
            context.insert(PersistedVisitEligibility(
                placeID: evidence.placeID,
                observedAt: evidence.observedAt,
                evidence: "distance=\(evidence.distanceMeters),accuracy=\(evidence.horizontalAccuracyMeters)",
                expiresAt: expiresAt
            ))
        }
        try? context.save()
    }

    func isEligible(placeID: UUID, now: Date = .now) -> Bool {
        guard let record = (try? context.fetch(FetchDescriptor<PersistedVisitEligibility>()))?.first(where: { $0.placeID == placeID }) else { return false }
        return record.expiresAt >= now
    }
}

@MainActor
final class SwiftDataTripStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        trips = (try? context.fetch(FetchDescriptor<PersistedTrip>()).map(\.value)) ?? []
    }

    func add(_ trip: Trip) {
        context.insert(PersistedTrip(trip))
        saveAndReload()
    }

    func update(_ trip: Trip) {
        guard let stored = (try? context.fetch(FetchDescriptor<PersistedTrip>()))?.first(where: { $0.id == trip.id }) else { return }
        stored.name = trip.name
        stored.startDate = trip.startDate
        stored.endDate = trip.endDate
        stored.destinations = trip.destinations
        stored.stops = trip.stops
        saveAndReload()
    }

    func remove(id: UUID) {
        if let stored = (try? context.fetch(FetchDescriptor<PersistedTrip>()))?.first(where: { $0.id == id }) {
            context.delete(stored)
            saveAndReload()
        }
    }

    private func saveAndReload() {
        try? context.save()
        reload()
    }
}

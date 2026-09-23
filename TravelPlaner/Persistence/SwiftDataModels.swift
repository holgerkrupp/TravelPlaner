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

enum TravelPlanerSchema {
    static let models: [any PersistentModel.Type] = [
        PersistedTrip.self,
        PersistedInterestSelection.self,
        PersistedVisitEligibility.self
    ]

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(models), configurations: configuration)
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

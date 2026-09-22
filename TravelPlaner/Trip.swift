import Foundation
import Combine

/// The core unit planned by TravelPlaner.
struct Trip: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var startDate: Date?
    var endDate: Date?
    var destinations: [String]

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        destinations: [String] = []
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.destinations = destinations
    }
}

/// In-memory source of truth for the current set of trips.
@MainActor
final class TripStore: ObservableObject {
    @Published private(set) var trips: [Trip]

    init(trips: [Trip] = []) {
        self.trips = trips
    }

    func add(_ trip: Trip) {
        trips.append(trip)
    }

    func update(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
    }

    func remove(id: Trip.ID) {
        trips.removeAll { $0.id == id }
    }
}

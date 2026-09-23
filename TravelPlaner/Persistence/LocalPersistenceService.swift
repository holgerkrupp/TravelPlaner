import Foundation

protocol LocalPersistenceService: Sendable {
    func loadTrips() async throws -> [Trip]
    func save(_ trips: [Trip]) async throws
}

actor InMemoryLocalPersistenceService: LocalPersistenceService {
    private var trips: [Trip]

    init(trips: [Trip] = []) { self.trips = trips }

    func loadTrips() async throws -> [Trip] { trips }
    func save(_ trips: [Trip]) async throws { self.trips = trips }
}

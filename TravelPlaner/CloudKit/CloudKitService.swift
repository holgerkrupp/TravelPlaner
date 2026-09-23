import CloudKit
import Foundation

protocol CloudKitService: Sendable {
    func fetchPlaces(in region: CoverageRegion) async throws -> [Place]
    func publish(_ places: [Place]) async throws
}

struct UnavailableCloudKitService: CloudKitService {
    func fetchPlaces(in region: CoverageRegion) async throws -> [Place] { [] }
    func publish(_ places: [Place]) async throws { }
}

/// The CloudKit boundary is intentionally small; record mapping belongs in a later issue.
struct PublicCloudKitService: CloudKitService {
    private let database: CKDatabase

    init(database: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.database = database
    }

    func fetchPlaces(in region: CoverageRegion) async throws -> [Place] {
        // Query construction is deliberately deferred until the Place schema issue.
        _ = database
        _ = region
        return []
    }

    func publish(_ places: [Place]) async throws {
        _ = database
        _ = places
    }
}

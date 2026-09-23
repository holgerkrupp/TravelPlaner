import CloudKit
import Foundation

enum CloudKitConfiguration {
    static let containerIdentifier = "iCloud.de.holgerkrupp.travelplaner"
}

protocol CloudKitService: Sendable {
    func fetchPlaces(in region: CoverageRegion) async throws -> [Place]
    func fetchPlace(stableID: UUID) async throws -> Place?
    func publish(_ places: [Place]) async throws
}

struct UnavailableCloudKitService: CloudKitService {
    func fetchPlaces(in region: CoverageRegion) async throws -> [Place] { [] }
    func fetchPlace(stableID: UUID) async throws -> Place? { nil }
    func publish(_ places: [Place]) async throws { }
}

/// The CloudKit boundary is intentionally small; record mapping belongs in a later issue.
struct PublicCloudKitService: CloudKitService {
    private let injectedDatabase: CKDatabase?

    init(database: CKDatabase? = nil) {
        self.injectedDatabase = database
    }

    func fetchPlaces(in region: CoverageRegion) async throws -> [Place] {
        let database = injectedDatabase ?? CKContainer(identifier: CloudKitConfiguration.containerIdentifier).publicCloudDatabase
        let query = CKQuery(recordType: CloudKitPlaceRecordMapper.recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
            } else {
                page = try await database.records(matching: query, resultsLimit: 100)
            }
            records.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
            cursor = page.queryCursor
        } while cursor != nil

        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        return records.compactMap { record -> Place? in
            guard let place = try? CloudKitPlaceRecordMapper.makePlace(from: record) else { return nil }
            let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            return center.distance(from: location) <= region.radius ? place : nil
        }
    }

    func fetchPlace(stableID: UUID) async throws -> Place? {
        let database = injectedDatabase ?? CKContainer(identifier: CloudKitConfiguration.containerIdentifier).publicCloudDatabase
        let query = CKQuery(recordType: CloudKitPlaceRecordMapper.recordType, predicate: NSPredicate(format: "stableID == %@", stableID.uuidString))
        let page = try await database.records(matching: query, resultsLimit: 1)
        return page.matchResults.compactMap { try? CloudKitPlaceRecordMapper.makePlace(from: $0.1.get()) }.first
    }

    func publish(_ places: [Place]) async throws {
        let database = injectedDatabase ?? CKContainer(identifier: CloudKitConfiguration.containerIdentifier).publicCloudDatabase
        let records = try places.map(CloudKitPlaceRecordMapper.makeRecord)
        for record in records {
            do {
                _ = try await database.save(record)
            } catch let error as CKError where error.code == .serverRecordChanged {
                // The deterministic record ID means another device already published
                // this source object. Resolve the existing record so the foreground
                // operation converges without creating a random duplicate.
                _ = try? await database.record(for: record.recordID)
                continue
            }
        }
    }
}

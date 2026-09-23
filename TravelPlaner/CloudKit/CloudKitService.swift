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
        let query = CKQuery(recordType: CloudKitPlaceRecordMapper.recordType, predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 100
        var records: [CKRecord] = []
        return try await withCheckedThrowingContinuation { continuation in
            operation.recordMatchedBlock = { _, result in
                if case let .success(record) = result { records.append(record) }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
                    let places = records.compactMap { record -> Place? in
                        guard let place = try? CloudKitPlaceRecordMapper.makePlace(from: record) else { return nil }
                        let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
                        return center.distance(from: location) <= region.radius ? place : nil
                    }
                    continuation.resume(returning: places)
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    func publish(_ places: [Place]) async throws {
        let records = try places.map(CloudKitPlaceRecordMapper.makeRecord)
        guard !records.isEmpty else { return }
        _ = try await database.modifyRecords(saving: records, deleting: [])
    }
}

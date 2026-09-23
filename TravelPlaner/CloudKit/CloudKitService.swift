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
                    let places = records.compactMap { try? CloudKitPlaceRecordMapper.makePlace(from: $0) }
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

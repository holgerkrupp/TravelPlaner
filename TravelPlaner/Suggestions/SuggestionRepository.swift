import CloudKit
import Foundation

protocol SuggestionCloudService: Sendable {
    func submit(_ suggestion: PlaceSuggestion) async throws
}

struct UnavailableSuggestionCloudService: SuggestionCloudService {
    func submit(_ suggestion: PlaceSuggestion) async throws { }
}

struct CloudKitSuggestionService: SuggestionCloudService {
    private let injectedDatabase: CKDatabase?

    init(database: CKDatabase? = nil) {
        self.injectedDatabase = database
    }

    func submit(_ suggestion: PlaceSuggestion) async throws {
        let database = injectedDatabase ?? CKContainer(identifier: CloudKitConfiguration.containerIdentifier).publicCloudDatabase
        let record = CKRecord(recordType: "PlaceSuggestion", recordID: CKRecord.ID(recordName: "suggestion_\(suggestion.id.uuidString)"))
        record["name"] = suggestion.name as NSString
        record["latitude"] = suggestion.coordinate.latitude as NSNumber
        record["longitude"] = suggestion.coordinate.longitude as NSNumber
        record["category"] = suggestion.category.rawValue as NSString
        record["interests"] = suggestion.interests.map(\.rawValue) as NSArray
        record["reason"] = suggestion.reason as NSString
        record["sourceURLs"] = suggestion.sourceURLs.map(\.absoluteString) as NSArray
        record["status"] = suggestion.status.rawValue as NSString
        record["createdAt"] = suggestion.createdAt as NSDate
        _ = try await database.save(record)
    }
}

actor SuggestionCoordinator {
    private let cloud: any SuggestionCloudService

    init(cloud: any SuggestionCloudService = UnavailableSuggestionCloudService()) { self.cloud = cloud }
    func submit(_ suggestion: PlaceSuggestion) async throws { try await cloud.submit(suggestion) }
}

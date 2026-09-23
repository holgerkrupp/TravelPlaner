import CloudKit
import CryptoKit
import Foundation

protocol VoteCloudService: Sendable {
    func save(_ vote: PlaceVote) async throws
    func fetchVotes(for placeID: UUID) async throws -> [PlaceVote]
}

struct UnavailableVoteCloudService: VoteCloudService {
    func save(_ vote: PlaceVote) async throws { }
    func fetchVotes(for placeID: UUID) async throws -> [PlaceVote] { [] }
}

struct CloudKitVoteService: VoteCloudService {
    private let container: CKContainer
    private let database: CKDatabase
    private let userKey: String

    init(container: CKContainer = CKContainer(identifier: CloudKitConfiguration.containerIdentifier), userKey: String) {
        self.container = container
        self.database = container.publicCloudDatabase
        self.userKey = userKey
    }

    func save(_ vote: PlaceVote) async throws {
        let record = CKRecord(recordType: "PlaceVote", recordID: recordID(for: vote.placeID))
        record["placeID"] = vote.placeID.uuidString as NSString
        record["value"] = vote.value.rawValue as NSString
        record["verificationType"] = vote.verification.rawValue as NSString
        record["updatedAt"] = vote.updatedAt as NSDate
        if let month = vote.coarseVisitMonth { record["visitMonth"] = month as NSDate }
        do { _ = try await database.save(record) }
        catch let error as CKError where error.code == .serverRecordChanged {
            // Fetching the existing record is intentionally the conflict path;
            // callers can retry with the current value instead of creating a duplicate.
            throw VoteError.conflict
        }
    }

    func fetchVotes(for placeID: UUID) async throws -> [PlaceVote] {
        let query = CKQuery(recordType: "PlaceVote", predicate: NSPredicate(format: "placeID == %@", placeID.uuidString))
        let result = try await database.records(matching: query, resultsLimit: 100)
        return result.matchResults.compactMap { _, value in
            guard let record = try? value.get(),
                  let rawValue = record["value"] as? String,
                  let value = VoteValue(rawValue: rawValue),
                  let rawVerification = record["verificationType"] as? String,
                  let verification = VoteVerificationType(rawValue: rawVerification) else { return nil }
            return PlaceVote(
                id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
                placeID: placeID,
                value: value,
                verification: verification,
                coarseVisitMonth: record["visitMonth"] as? Date,
                updatedAt: record["updatedAt"] as? Date ?? .distantPast
            )
        }
    }

    private func recordID(for placeID: UUID) -> CKRecord.ID {
        let input = Data("\(userKey):\(placeID.uuidString)".utf8)
        let digest = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        return CKRecord.ID(recordName: "vote_\(digest)")
    }

    enum VoteError: Error { case conflict }
}

actor VoteCoordinator {
    private let cloud: any VoteCloudService

    init(cloud: any VoteCloudService = UnavailableVoteCloudService()) { self.cloud = cloud }

    func submit(_ vote: PlaceVote, eligibility: VisitEligibility) async throws {
        guard eligibility.isEligible else { throw CoordinatorError.visitNotVerified }
        try await cloud.save(vote)
    }

    func aggregate(for placeID: UUID) async -> VoteAggregate {
        let votes = (try? await cloud.fetchVotes(for: placeID)) ?? []
        return VoteAggregator.aggregate(votes)
    }

    enum CoordinatorError: Error { case visitNotVerified }
}

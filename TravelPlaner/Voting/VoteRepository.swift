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

    static func forCurrentUser(container: CKContainer = CKContainer(identifier: CloudKitConfiguration.containerIdentifier)) async throws -> Self {
        let userRecord = try await container.userRecordID()
        return Self(container: container, userKey: userRecord.recordName)
    }

    func save(_ vote: PlaceVote) async throws {
        let record = CKRecord(recordType: "PlaceVote", recordID: Self.recordID(userKey: userKey, placeID: vote.placeID))
        Self.apply(vote, to: record)
        do { _ = try await database.save(record) }
        catch let error as CKError where error.code == .serverRecordChanged {
            // A record owned by this account may already exist. Fetch its change tag,
            // apply the new vote, and save it so changing a vote works without
            // requiring arbitrary clients to edit somebody else's records.
            let existing = try await database.record(for: record.recordID)
            Self.apply(vote, to: existing)
            do {
                _ = try await database.save(existing)
            } catch let retryError as CKError where retryError.code == .serverRecordChanged {
                throw VoteError.conflict
            }
        }
    }

    private static func apply(_ vote: PlaceVote, to record: CKRecord) {
        record["placeID"] = vote.placeID.uuidString as NSString
        record["value"] = vote.value.rawValue as NSString
        record["verificationType"] = vote.verification.rawValue as NSString
        record["updatedAt"] = vote.updatedAt as NSDate
        record["visitMonth"] = vote.coarseVisitMonth as NSDate?
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

    static func recordID(userKey: String, placeID: UUID) -> CKRecord.ID {
        let input = Data("\(userKey):\(placeID.uuidString)".utf8)
        let digest = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        return CKRecord.ID(recordName: "vote_\(digest)")
    }

    enum VoteError: Error { case conflict }
}

actor VoteCoordinator {
    private let cloud: any VoteCloudService
    private let offlineQueue: OfflineWriteQueue?

    init(cloud: any VoteCloudService = UnavailableVoteCloudService(), offlineQueue: OfflineWriteQueue? = nil) {
        self.cloud = cloud
        self.offlineQueue = offlineQueue
    }

    func submit(_ vote: PlaceVote, eligibility: VisitEligibility) async throws {
        guard eligibility.isEligible else { throw CoordinatorError.visitNotVerified }
        do {
            try await cloud.save(vote)
        } catch {
            if let offlineQueue {
                await offlineQueue.enqueue(key: "vote:\(vote.placeID.uuidString)", operation: { [cloud] in
                    try await cloud.save(vote)
                })
            }
            throw error
        }
    }

    func aggregate(for placeID: UUID) async -> VoteAggregate {
        let votes = (try? await cloud.fetchVotes(for: placeID)) ?? []
        return VoteAggregator.aggregate(votes)
    }

    enum CoordinatorError: Error { case visitNotVerified }
}

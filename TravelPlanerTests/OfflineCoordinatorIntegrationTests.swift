import XCTest
@testable import TravelPlaner

private struct FailingVoteService: VoteCloudService {
    func save(_ vote: PlaceVote) async throws { throw TestFailure.unavailable }
    func fetchVotes(for placeID: UUID) async throws -> [PlaceVote] { [] }
}

private struct FailingSuggestionService: SuggestionCloudService {
    func submit(_ suggestion: PlaceSuggestion) async throws { throw TestFailure.unavailable }
}

private enum TestFailure: Error { case unavailable }

@MainActor
final class OfflineCoordinatorIntegrationTests: XCTestCase {
    func testFailedVoteIsQueuedForLaterRetry() async throws {
        let queue = OfflineWriteQueue()
        let placeID = UUID()
        let vote = PlaceVote(id: UUID(), placeID: placeID, value: .worthVisiting, verification: .currentProximity, updatedAt: .now)

        do {
            try await VoteCoordinator(cloud: FailingVoteService(), offlineQueue: queue)
                .submit(vote, eligibility: VisitEligibility(isEligible: true, reason: "test"))
            XCTFail("Expected the first write to fail")
        } catch { }

        let pending = await queue.pendingKeys()
        XCTAssertEqual(pending, ["vote:\(placeID.uuidString)"])
    }

    func testFailedSuggestionIsQueuedForLaterRetry() async throws {
        let queue = OfflineWriteQueue()
        let suggestion = try PlaceSuggestion(
            name: "Offline suggestion",
            coordinate: try GeoCoordinate(latitude: 48, longitude: 11),
            category: .unusual,
            reason: "Test"
        )

        do {
            try await SuggestionCoordinator(cloud: FailingSuggestionService(), offlineQueue: queue).submit(suggestion)
            XCTFail("Expected the first write to fail")
        } catch { }

        let pending = await queue.pendingKeys()
        XCTAssertEqual(pending, ["suggestion:\(suggestion.id.uuidString)"])
    }
}

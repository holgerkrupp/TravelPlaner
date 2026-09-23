import XCTest
@testable import TravelPlaner

actor AttemptCounter {
    var attempts = 0
    func next() -> Int { attempts += 1; return attempts }
}

@MainActor
final class OfflineWriteQueueTests: XCTestCase {
    func testFlushRetriesTransientFailureAndRemovesCompletedWrite() async {
        let queue = OfflineWriteQueue()
        let counter = AttemptCounter()
        await queue.enqueue(key: "vote:place", operation: {
            if await counter.next() < 2 { throw TestError.transient }
        })

        let completed = await queue.flush(policy: OfflineRetryPolicy(maximumAttempts: 3, backoffNanoseconds: 0))
        let pending = await queue.pendingKeys()
        XCTAssertEqual(completed, ["vote:place"])
        XCTAssertEqual(pending, [])
    }

    func testFlushLeavesPermanentlyFailedWriteQueued() async {
        let queue = OfflineWriteQueue()
        await queue.enqueue(key: "suggestion:place", operation: { throw TestError.permanent })

        let completed = await queue.flush(policy: OfflineRetryPolicy(maximumAttempts: 2, backoffNanoseconds: 0))
        let pending = await queue.pendingKeys()
        XCTAssertTrue(completed.isEmpty)
        XCTAssertEqual(pending, ["suggestion:place"])
    }

    private enum TestError: Error { case transient, permanent }
}

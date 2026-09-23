import Foundation

nonisolated struct OfflineRetryPolicy: Sendable, Equatable {
    let maximumAttempts: Int
    let backoffNanoseconds: UInt64

    nonisolated init(maximumAttempts: Int = 3, backoffNanoseconds: UInt64 = 250_000_000) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.backoffNanoseconds = backoffNanoseconds
    }
}

/// Keeps CloudKit writes alive across transient connectivity failures during the app session.
/// The payload remains owned by the caller; this queue never stores movement or visit history.
actor OfflineWriteQueue {
    typealias Operation = @Sendable () async throws -> Void

    private var operations: [String: Operation] = [:]

    func enqueue(key: String, operation: @escaping Operation) {
        operations[key] = operation
    }

    func pendingKeys() -> [String] { operations.keys.sorted() }

    @discardableResult
    func flush(policy: OfflineRetryPolicy = OfflineRetryPolicy()) async -> [String] {
        let queued = operations
        var completed: [String] = []
        for key in queued.keys.sorted() {
            guard let operation = queued[key] else { continue }
            var succeeded = false
            for attempt in 0..<policy.maximumAttempts {
                do {
                    try await operation()
                    succeeded = true
                    break
                } catch {
                    if attempt + 1 < policy.maximumAttempts, policy.backoffNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: policy.backoffNanoseconds)
                    }
                }
            }
            if succeeded {
                operations.removeValue(forKey: key)
                completed.append(key)
            }
        }
        return completed
    }
}

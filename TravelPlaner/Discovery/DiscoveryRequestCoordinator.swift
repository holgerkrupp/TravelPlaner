import Foundation
import CoreLocation

/// Coalesces identical discovery requests while allowing callers to cancel their own wait.
/// The shared operation is not cancelled when one view disappears because another consumer may
/// still need the result for the same corridor/region.
actor DiscoveryRequestCoordinator {
    private let pipeline: any POIDiscoveryService
    private var inFlight: [RequestKey: Task<[Place], Error>] = [:]

    init(pipeline: any POIDiscoveryService) {
        self.pipeline = pipeline
    }

    func discover(for request: DiscoveryRequest) async throws -> [Place] {
        let key = RequestKey(request)
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let pipeline = self.pipeline
        let task = Task { try await pipeline.discover(for: request) }
        inFlight[key] = task
        defer { inFlight.removeValue(forKey: key) }
        return try await task.value
    }

    private struct RequestKey: Hashable, Sendable {
        let latitude: Int
        let longitude: Int
        let radius: Int

        init(_ request: DiscoveryRequest) {
            // Quantize to 100 m so tiny camera changes do not defeat coalescing.
            latitude = Int((request.center.latitude * 10_000).rounded())
            longitude = Int((request.center.longitude * 10_000).rounded())
            radius = Int(request.radius.rounded())
        }
    }
}

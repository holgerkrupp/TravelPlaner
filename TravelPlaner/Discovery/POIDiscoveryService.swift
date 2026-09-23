import Foundation

protocol POIDiscoveryService: Sendable {
    func discover(for request: DiscoveryRequest) async throws -> [Place]
}

struct EmptyPOIDiscoveryService: POIDiscoveryService {
    func discover(for request: DiscoveryRequest) async throws -> [Place] { [] }
}

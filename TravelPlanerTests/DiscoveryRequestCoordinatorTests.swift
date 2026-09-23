import CoreLocation
import XCTest
@testable import TravelPlaner

private actor DiscoveryCallCounter {
    var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}

private struct CountingDiscoveryService: POIDiscoveryService {
    let counter: DiscoveryCallCounter

    func discover(for request: DiscoveryRequest) async throws -> [Place] {
        await counter.increment()
        try await Task.sleep(nanoseconds: 30_000_000)
        return []
    }
}

@MainActor
final class DiscoveryRequestCoordinatorTests: XCTestCase {
    func testIdenticalRequestsShareOnePipelineCall() async throws {
        let counter = DiscoveryCallCounter()
        let coordinator = DiscoveryRequestCoordinator(pipeline: CountingDiscoveryService(counter: counter))
        let request = DiscoveryRequest(center: CLLocationCoordinate2D(latitude: 48, longitude: 11), radius: 10_000)

        async let first = coordinator.discover(for: request)
        async let second = coordinator.discover(for: request)
        _ = try await (first, second)

        let calls = await counter.value()
        XCTAssertEqual(calls, 1)
    }
}

import CoreLocation
import Foundation

struct Route: Equatable, Sendable {
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
}

struct DiscoveryRequest: Equatable, Sendable {
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance

    static func == (lhs: DiscoveryRequest, rhs: DiscoveryRequest) -> Bool {
        lhs.center.latitude == rhs.center.latitude && lhs.center.longitude == rhs.center.longitude && lhs.radius == rhs.radius
    }
}

struct CoverageRegion: Equatable, Sendable {
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance

    static func == (lhs: CoverageRegion, rhs: CoverageRegion) -> Bool {
        lhs.center.latitude == rhs.center.latitude && lhs.center.longitude == rhs.center.longitude && lhs.radius == rhs.radius
    }

}

struct VisitEligibility: Equatable, Sendable {
    let isEligible: Bool
    let reason: String?
}

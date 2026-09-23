import CoreLocation
import Foundation

protocol RouteService: Sendable {
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> Route
}

struct UnavailableRouteService: RouteService {
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> Route {
        throw AppServiceError.routeUnavailable
    }
}

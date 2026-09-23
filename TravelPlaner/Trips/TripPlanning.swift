import CoreLocation
import Foundation
import MapKit

struct TripStop: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var coordinate: GeoCoordinate
    var order: Int

    init(id: UUID = UUID(), name: String, coordinate: GeoCoordinate, order: Int) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.order = order
    }
}

struct RouteCorridor: Equatable, Sendable {
    let stops: [TripStop]
    let widthMeters: CLLocationDistance

    nonisolated init(stops: [TripStop], widthMeters: CLLocationDistance) {
        self.stops = stops
        self.widthMeters = widthMeters
    }
}

struct RouteCandidateFilter: Sendable {
    let corridor: RouteCorridor

    nonisolated func isNearCorridor(_ place: Place, approximateDistanceMeters: CLLocationDistance) -> Bool {
        guard !corridor.stops.isEmpty else { return false }
        return corridor.stops.contains { stop in
            let from = CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude)
            let to = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            return from.distance(from: to) <= corridor.widthMeters + approximateDistanceMeters
        }
    }
}

struct MapKitRouteService: RouteService {
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> Route {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw AppServiceError.routeUnavailable }
        return Route(distance: route.distance, expectedTravelTime: route.expectedTravelTime)
    }
}

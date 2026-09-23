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
        let threshold = corridor.widthMeters + approximateDistanceMeters
        let coordinates = corridor.stops.map(\.coordinate)
        if coordinates.count == 1 {
            return distance(from: place.coordinate, to: coordinates[0]) <= threshold
        }
        return zip(coordinates, coordinates.dropFirst()).contains { start, end in
            distanceFromPoint(place.coordinate, toSegmentFrom: start, to: end) <= threshold
        }
    }

    private nonisolated func distance(from lhs: GeoCoordinate, to rhs: GeoCoordinate) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    /// Uses a local east/north projection for the short segments used by a route corridor.
    /// This avoids excluding places that lie between two distant trip stops.
    private nonisolated func distanceFromPoint(
        _ point: GeoCoordinate,
        toSegmentFrom start: GeoCoordinate,
        to end: GeoCoordinate
    ) -> CLLocationDistance {
        let latitudeScale = 111_320.0
        let longitudeScale = 111_320.0 * cos(((start.latitude + end.latitude + point.latitude) / 3) * .pi / 180)
        let startX = start.longitude * longitudeScale
        let startY = start.latitude * latitudeScale
        let endX = end.longitude * longitudeScale
        let endY = end.latitude * latitudeScale
        let pointX = point.longitude * longitudeScale
        let pointY = point.latitude * latitudeScale
        let dx = endX - startX
        let dy = endY - startY
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(pointX - startX, pointY - startY)
        }
        let projection = max(0, min(1, ((pointX - startX) * dx + (pointY - startY) * dy) / lengthSquared))
        let closestX = startX + projection * dx
        let closestY = startY + projection * dy
        return hypot(pointX - closestX, pointY - closestY)
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

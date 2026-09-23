import CoreLocation
import Foundation

struct DetourCandidate: Equatable, Identifiable, Sendable {
    let id: UUID
    let place: Place
    let score: DiscoveryScore
    let approximateDetour: Route?
}

actor TripDiscoveryCoordinator {
    private let discovery: any POIDiscoveryService
    private let route: any RouteService
    private let ranker: DiscoveryRanker

    init(
        discovery: any POIDiscoveryService,
        route: any RouteService,
        ranker: DiscoveryRanker
    ) {
        self.discovery = discovery
        self.route = route
        self.ranker = ranker
    }

    func discover(for trip: Trip) async throws -> [DetourCandidate] {
        guard trip.stops.count >= 2 else { return [] }
        let center = averageCoordinate(of: trip.stops)
        let radius = max(10_000, trip.stops.reduce(0) { partial, stop in
            max(partial, distance(from: center, to: stop.coordinate))
        })
        let places = try await discovery.discover(for: DiscoveryRequest(center: center.coreLocation, radius: radius))
        let filter = RouteCandidateFilter(corridor: RouteCorridor(stops: trip.stops, widthMeters: 20_000))
        let ranked = ranker.rank(places.compactMap { place -> (Place, RankingInputs)? in
            guard filter.isNearCorridor(place, approximateDistanceMeters: 0) else { return nil }
            let nearestDistance = trip.stops.map { distance(from: place.coordinate, to: $0.coordinate) }.min() ?? radius
            let relevance = max(0, min(1, 1 - nearestDistance / 20_000))
            return (place, RankingInputs(baseNotability: place.baseNotability, uniqueness: place.baseNotability, routeRelevance: relevance))
        })
        var result: [DetourCandidate] = []
        for (place, score) in ranked.prefix(5) {
            try Task.checkCancellation()
            let first = trip.stops[0].coordinate
            let last = trip.stops[trip.stops.count - 1].coordinate
            let toPlace = try? await route.calculateRoute(from: first.coreLocation, to: place.coordinate.coreLocation)
            let fromPlace = try? await route.calculateRoute(from: place.coordinate.coreLocation, to: last.coreLocation)
            let detour: Route? = if let toPlace, let fromPlace {
                Route(distance: toPlace.distance + fromPlace.distance, expectedTravelTime: toPlace.expectedTravelTime + fromPlace.expectedTravelTime)
            } else { nil }
            result.append(DetourCandidate(id: place.id, place: place, score: score, approximateDetour: detour))
        }
        return result
    }

    private func averageCoordinate(of stops: [TripStop]) -> GeoCoordinate {
        let latitude = stops.map(\.coordinate.latitude).reduce(0, +) / Double(stops.count)
        let longitude = stops.map(\.coordinate.longitude).reduce(0, +) / Double(stops.count)
        return try! GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    private func distance(from lhs: GeoCoordinate, to rhs: GeoCoordinate) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}

private extension GeoCoordinate {
    var coreLocation: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

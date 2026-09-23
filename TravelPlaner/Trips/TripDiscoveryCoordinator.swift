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
        let stops = trip.stops.sorted { $0.order < $1.order }
        guard stops.count >= 2 else { return [] }
        let center = averageCoordinate(of: stops)
        let radius = max(10_000, stops.reduce(0) { partial, stop in
            max(partial, distance(from: center, to: stop.coordinate))
        })
        let places = try await discovery.discover(for: DiscoveryRequest(center: center.coreLocation, radius: radius))
        let filter = RouteCandidateFilter(corridor: RouteCorridor(stops: stops, widthMeters: 20_000))
        let rankingInputs = places.compactMap { place -> (Place, RankingInputs)? in
            guard filter.isNearCorridor(place, approximateDistanceMeters: 0) else { return nil }
            let relevance = corridorRelevance(place: place, stops: stops, widthMeters: 20_000)
            return (place, RankingInputs(baseNotability: place.baseNotability, uniqueness: place.baseNotability, routeRelevance: relevance))
        }
        let ranked = ranker.rank(rankingInputs)
        let inputByPlaceID = Dictionary(uniqueKeysWithValues: rankingInputs.map { ($0.0.id, $0.1) })
        let baseRoutes = await calculateBaseRoutes(for: stops)
        var result: [DetourCandidate] = []
        for (place, score) in ranked.prefix(5) {
            try Task.checkCancellation()
            let detour = await calculateDetour(for: place, stops: stops, baseRoutes: baseRoutes)
            var finalScore = score
            if let detour, var inputs = inputByPlaceID[place.id] {
                inputs.detourPenalty = min(1, detour.expectedTravelTime / (30 * 60))
                finalScore = ranker.score(inputs)
            }
            result.append(DetourCandidate(id: place.id, place: place, score: finalScore, approximateDetour: detour))
        }
        return result.sorted {
            if $0.score.total != $1.score.total { return $0.score.total > $1.score.total }
            return $0.place.id.uuidString < $1.place.id.uuidString
        }
    }

    private func calculateBaseRoutes(for stops: [TripStop]) async -> [Route?] {
        await withTaskGroup(of: (Int, Route?).self, returning: [Route?].self) { group in
            for (index, pair) in zip(stops, stops.dropFirst()).enumerated() {
                group.addTask {
                    let route = try? await self.route.calculateRoute(
                        from: pair.0.coordinate.coreLocation,
                        to: pair.1.coordinate.coreLocation
                    )
                    return (index, route)
                }
            }
            var routes = Array<Route?>(repeating: nil, count: max(0, stops.count - 1))
            for await (index, route) in group { routes[index] = route }
            return routes
        }
    }

    private func calculateDetour(for place: Place, stops: [TripStop], baseRoutes: [Route?]) async -> Route? {
        guard stops.count >= 2 else { return nil }
        return await withTaskGroup(of: Route?.self, returning: Route?.self) { group in
            for (index, pair) in zip(stops, stops.dropFirst()).enumerated() {
                group.addTask {
                    guard let viaStart = try? await self.route.calculateRoute(
                        from: pair.0.coordinate.coreLocation,
                        to: place.coordinate.coreLocation
                    ), let viaEnd = try? await self.route.calculateRoute(
                        from: place.coordinate.coreLocation,
                        to: pair.1.coordinate.coreLocation
                    ) else { return nil }
                    let viaDistance = viaStart.distance + viaEnd.distance
                    let viaTime = viaStart.expectedTravelTime + viaEnd.expectedTravelTime
                    let base = baseRoutes[index]
                    return Route(
                        distance: max(0, viaDistance - (base?.distance ?? 0)),
                        expectedTravelTime: max(0, viaTime - (base?.expectedTravelTime ?? 0))
                    )
                }
            }
            var best: Route?
            for await candidate in group {
                guard let candidate else { continue }
                if let current = best {
                    if candidate.expectedTravelTime < current.expectedTravelTime { best = candidate }
                } else {
                    best = candidate
                }
            }
            return best
        }
    }

    private func corridorRelevance(place: Place, stops: [TripStop], widthMeters: CLLocationDistance) -> Double {
        let nearest = stops.indices.dropLast().map { index in
            distanceFromPoint(place.coordinate, start: stops[index].coordinate, end: stops[index + 1].coordinate)
        }.min() ?? widthMeters
        return max(0, min(1, 1 - nearest / widthMeters))
    }

    private func distanceFromPoint(_ point: GeoCoordinate, start: GeoCoordinate, end: GeoCoordinate) -> CLLocationDistance {
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
        guard lengthSquared > 0 else { return hypot(pointX - startX, pointY - startY) }
        let projection = max(0, min(1, ((pointX - startX) * dx + (pointY - startY) * dy) / lengthSquared))
        return hypot(pointX - (startX + projection * dx), pointY - (startY + projection * dy))
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

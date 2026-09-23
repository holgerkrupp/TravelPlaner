import Foundation

struct AppDependencies: Sendable {
    let cloudKit: any CloudKitService
    let location: any LocationService
    let route: any RouteService
    let discovery: any POIDiscoveryService
    let persistence: any LocalPersistenceService

    init(
        cloudKit: any CloudKitService = UnavailableCloudKitService(),
        location: any LocationService = UnavailableLocationService(),
        route: any RouteService = UnavailableRouteService(),
        discovery: any POIDiscoveryService = EmptyPOIDiscoveryService(),
        persistence: any LocalPersistenceService = InMemoryLocalPersistenceService()
    ) {
        self.cloudKit = cloudKit
        self.location = location
        self.route = route
        self.discovery = discovery
        self.persistence = persistence
    }

    static let preview = AppDependencies()
}

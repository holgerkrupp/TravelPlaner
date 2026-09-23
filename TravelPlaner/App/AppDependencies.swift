import Foundation

struct AppDependencies: Sendable {
    let cloudKit: any CloudKitService
    let location: any LocationService
    let route: any RouteService
    let discovery: any POIDiscoveryService
    let persistence: any LocalPersistenceService

    init(
        cloudKit: any CloudKitService = PublicCloudKitService(),
        location: any LocationService = UnavailableLocationService(),
        route: any RouteService = MapKitRouteService(),
        discovery: any POIDiscoveryService = DiscoveryPipeline(cloudKit: PublicCloudKitService(), adapters: [], evaluator: CoverageEvaluator(policy: CoveragePolicy())),
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

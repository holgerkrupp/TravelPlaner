import CoreLocation
import Foundation

protocol LocationService: Sendable {
    func authorizationStatus() async -> CLAuthorizationStatus
    func currentLocation() async throws -> CLLocation
}

struct UnavailableLocationService: LocationService {
    func authorizationStatus() async -> CLAuthorizationStatus { .notDetermined }
    func currentLocation() async throws -> CLLocation { throw AppServiceError.locationUnavailable }
}

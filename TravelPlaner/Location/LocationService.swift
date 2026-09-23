import CoreLocation
import Foundation

@MainActor
protocol LocationService: Sendable {
    func authorizationStatus() async -> CLAuthorizationStatus
    func currentLocation() async throws -> CLLocation
}

@MainActor
struct UnavailableLocationService: LocationService {
    func authorizationStatus() async -> CLAuthorizationStatus { .notDetermined }
    func currentLocation() async throws -> CLLocation { throw AppServiceError.locationUnavailable }
}

@MainActor
final class CoreLocationService: NSObject, CLLocationManagerDelegate, LocationService, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func authorizationStatus() async -> CLAuthorizationStatus { manager.authorizationStatus }

    func currentLocation() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted: throw AppServiceError.locationUnavailable
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

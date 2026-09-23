import CoreLocation
import Foundation

struct VisitEvidence: Equatable, Sendable {
    let placeID: UUID
    let observedAt: Date
    let distanceMeters: CLLocationDistance
    let horizontalAccuracyMeters: CLLocationAccuracy
}

struct VisitEligibilityPolicy: Equatable, Sendable {
    var maximumAccuracyMeters: CLLocationAccuracy = 150
    var maximumAge: TimeInterval = 15 * 60
    var defaultRadiusMeters: CLLocationDistance = 250
}

struct VisitEligibilityEvaluator: Sendable {
    let policy: VisitEligibilityPolicy

    func evaluate(place: Place, location: CLLocation, now: Date = .now) -> VisitEvidence? {
        guard location.timestamp <= now,
              now.timeIntervalSince(location.timestamp) <= policy.maximumAge,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= policy.maximumAccuracyMeters else { return nil }
        let target = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        let radius = place.boundingRadiusMeters ?? policy.defaultRadiusMeters
        let distance = location.distance(from: target)
        guard distance <= radius else { return nil }
        return VisitEvidence(placeID: place.id, observedAt: location.timestamp, distanceMeters: distance, horizontalAccuracyMeters: location.horizontalAccuracy)
    }
}

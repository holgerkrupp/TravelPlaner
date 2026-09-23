import CoreLocation
import Foundation

struct PlaceID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

struct Place: Identifiable, Codable, Equatable, Sendable {
    let id: PlaceID
    var name: String
    var coordinate: CLLocationCoordinate2D
    var reasonToVisit: String?

    static func == (lhs: Place, rhs: Place) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude && lhs.reasonToVisit == rhs.reasonToVisit
    }

    enum CodingKeys: String, CodingKey { case id, name, latitude, longitude, reasonToVisit }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(PlaceID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        coordinate = CLLocationCoordinate2D(
            latitude: try values.decode(CLLocationDegrees.self, forKey: .latitude),
            longitude: try values.decode(CLLocationDegrees.self, forKey: .longitude)
        )
        reasonToVisit = try values.decodeIfPresent(String.self, forKey: .reasonToVisit)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(coordinate.latitude, forKey: .latitude)
        try values.encode(coordinate.longitude, forKey: .longitude)
        try values.encodeIfPresent(reasonToVisit, forKey: .reasonToVisit)
    }
}

struct Route: Equatable, Sendable {
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
}

struct DiscoveryRequest: Equatable, Sendable {
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance

    static func == (lhs: DiscoveryRequest, rhs: DiscoveryRequest) -> Bool {
        lhs.center.latitude == rhs.center.latitude && lhs.center.longitude == rhs.center.longitude && lhs.radius == rhs.radius
    }
}

struct CoverageRegion: Equatable, Sendable {
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance

    static func == (lhs: CoverageRegion, rhs: CoverageRegion) -> Bool {
        lhs.center.latitude == rhs.center.latitude && lhs.center.longitude == rhs.center.longitude && lhs.radius == rhs.radius
    }
}

struct VisitEligibility: Equatable, Sendable {
    let isEligible: Bool
    let reason: String?
}

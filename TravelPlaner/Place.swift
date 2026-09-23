import Foundation

/// A coordinate stored by the domain without coupling it to MapKit or Core Location.
struct GeoCoordinate: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude),
              latitude.isFinite, longitude.isFinite else {
            throw ValidationError.invalidCoordinate
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    enum ValidationError: Error, Equatable {
        case invalidCoordinate
    }
}

/// The source families TravelPlaner is allowed to retain as provenance.
enum PlaceSource: String, Codable, CaseIterable, Sendable {
    case wikidata
    case openStreetMap
    case wikimediaCommons
    case wikipedia
    case wikivoyage
    case officialTourism
    case appleMaps
    case other
}

/// A stable source identity. Display names are deliberately not identity.
struct PlaceSourceReference: Codable, Equatable, Hashable, Sendable {
    let source: PlaceSource
    let externalID: String
    var sourceURL: URL?
    var license: String?
    var attribution: String?

    init(
        source: PlaceSource,
        externalID: String,
        sourceURL: URL? = nil,
        license: String? = nil,
        attribution: String? = nil
    ) throws {
        let normalizedID = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { throw ValidationError.emptyExternalID }
        self.source = source
        self.externalID = normalizedID
        self.sourceURL = sourceURL
        self.license = license
        self.attribution = attribution
    }

    /// Suitable for deterministic local deduplication and CloudKit record names.
    nonisolated var canonicalKey: String { "\(source.rawValue):\(externalID)" }

    enum ValidationError: Error, Equatable {
        case emptyExternalID
    }
}

enum PlaceKind: String, Codable, CaseIterable, Sendable {
    case detourStop
    case dayTrip
    case majorDestination
    case remoteDestination
}

enum PlaceCategory: String, Codable, CaseIterable, Sendable {
    case nature
    case park
    case geology
    case museum
    case history
    case industrialHeritage
    case architecture
    case archaeology
    case viewpoint
    case culture
    case food
    case unusual
    case science
    case other
}

enum PlaceInterest: String, Codable, CaseIterable, Sendable {
    case nature, geology, hiking, architecture, engineering, aviation, railways
    case maritime, history, archaeology, art, science, technology, food
    case unusual, familyFriendly
}

/// Canonical, source-backed discovery data. User suggestions are intentionally a different type.
struct Place: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var alternateNames: [String]
    var coordinate: GeoCoordinate
    var boundingRadiusMeters: Double?
    var category: PlaceCategory
    var interests: Set<PlaceInterest>
    var kind: PlaceKind
    var editorialReason: String
    var sources: [PlaceSourceReference]
    var estimatedVisitDurationMinutes: Int?
    var baseNotability: Double

    init(
        id: UUID = UUID(),
        name: String,
        alternateNames: [String] = [],
        coordinate: GeoCoordinate,
        boundingRadiusMeters: Double? = nil,
        category: PlaceCategory,
        interests: Set<PlaceInterest> = [],
        kind: PlaceKind = .detourStop,
        editorialReason: String,
        sources: [PlaceSourceReference],
        estimatedVisitDurationMinutes: Int? = nil,
        baseNotability: Double = 0
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = editorialReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ValidationError.emptyName }
        guard !trimmedReason.isEmpty else { throw ValidationError.emptyEditorialReason }
        guard !sources.isEmpty else { throw ValidationError.missingProvenance }
        if let radius = boundingRadiusMeters, radius <= 0 || !radius.isFinite {
            throw ValidationError.invalidBoundingRadius
        }
        if let duration = estimatedVisitDurationMinutes, duration <= 0 {
            throw ValidationError.invalidVisitDuration
        }
        guard (0...1).contains(baseNotability), baseNotability.isFinite else {
            throw ValidationError.invalidNotability
        }

        self.id = id
        self.name = trimmedName
        self.alternateNames = alternateNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.coordinate = coordinate
        self.boundingRadiusMeters = boundingRadiusMeters
        self.category = category
        self.interests = interests
        self.kind = kind
        self.editorialReason = trimmedReason
        self.sources = sources
        self.estimatedVisitDurationMinutes = estimatedVisitDurationMinutes
        self.baseNotability = baseNotability
    }

    nonisolated var canonicalSourceKeys: Set<String> { Set(sources.map(\.canonicalKey)) }

    enum ValidationError: Error, Equatable {
        case emptyName
        case emptyEditorialReason
        case missingProvenance
        case invalidBoundingRadius
        case invalidVisitDuration
        case invalidNotability
    }
}

enum PlaceDeduplicator {
    /// Keeps the first record for each stable source identity, preserving input order.
    nonisolated static func unique(_ places: [Place]) -> [Place] {
        var seen = Set<String>()
        return places.filter { place in
            let keys = place.canonicalSourceKeys
            guard !keys.isEmpty, seen.isDisjoint(with: keys) else { return false }
            seen.formUnion(keys)
            return true
        }
    }
}

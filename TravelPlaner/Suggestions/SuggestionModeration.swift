import CoreLocation
import Foundation

struct SuggestionReview: Equatable, Sendable {
    let suggestion: PlaceSuggestion
    let likelyDuplicateIDs: [UUID]
}

enum SuggestionModerationEngine {
    static func review(_ suggestion: PlaceSuggestion, against places: [Place], duplicateRadiusMeters: CLLocationDistance = 250) -> SuggestionReview {
        let suggestionLocation = CLLocation(latitude: suggestion.coordinate.latitude, longitude: suggestion.coordinate.longitude)
        let normalizedName = normalize(suggestion.name)
        let duplicates = places.filter { place in
            let placeLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            let nearby = suggestionLocation.distance(from: placeLocation) <= duplicateRadiusMeters
            let sameName = normalize(place.name) == normalizedName || place.alternateNames.contains { normalize($0) == normalizedName }
            return nearby || sameName
        }.map(\.id)
        return SuggestionReview(suggestion: suggestion, likelyDuplicateIDs: duplicates)
    }

    /// Approval is deliberately explicit and requires a developer-supplied source reference.
    static func approve(_ suggestion: PlaceSuggestion, source: PlaceSourceReference, kind: PlaceKind = .detourStop) throws -> Place {
        try Place(
            id: suggestion.id,
            name: suggestion.name,
            coordinate: suggestion.coordinate,
            category: suggestion.category,
            interests: suggestion.interests,
            kind: kind,
            editorialReason: suggestion.reason,
            sources: [source]
        )
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()
    }
}

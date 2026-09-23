import Foundation

enum SuggestionStatus: String, Codable, Sendable { case pending, approved, rejected }

struct PlaceSuggestion: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var coordinate: GeoCoordinate
    var category: PlaceCategory
    var interests: Set<PlaceInterest>
    var reason: String
    var sourceURLs: [URL]
    var status: SuggestionStatus
    var createdAt: Date

    init(name: String, coordinate: GeoCoordinate, category: PlaceCategory, interests: Set<PlaceInterest> = [], reason: String, sourceURLs: [URL] = []) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedReason.isEmpty else { throw ValidationError.emptyText }
        self.id = UUID()
        self.name = trimmedName
        self.coordinate = coordinate
        self.category = category
        self.interests = interests
        self.reason = trimmedReason
        self.sourceURLs = sourceURLs
        self.status = .pending
        self.createdAt = .now
    }

    enum ValidationError: Error, Equatable { case emptyText }
}

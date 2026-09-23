import Foundation
import SwiftUI

struct PlaceImageAsset: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let remoteURL: URL
    let license: String
    let attribution: String
    let sourceURL: URL?
}

struct PlaceDetailView: View {
    let place: Place

    var body: some View {
        List {
            Section("Why visit") { Text(place.editorialReason) }
            Section("Details") {
                LabeledContent("Category", value: place.category.rawValue.capitalized)
                LabeledContent("Type", value: place.kind.rawValue)
                if let minutes = place.estimatedVisitDurationMinutes {
                    LabeledContent("Typical visit", value: "\(minutes) minutes")
                }
            }
            Section("Sources") {
                ForEach(place.sources, id: \.canonicalKey) { source in
                    VStack(alignment: .leading) {
                        Text(source.source.rawValue.capitalized)
                        Text(source.externalID).font(.caption).foregroundStyle(.secondary)
                        if let attribution = source.attribution { Text(attribution).font(.caption) }
                        if let license = source.license { Text(license).font(.caption).foregroundStyle(.secondary) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(place.name)
    }
}

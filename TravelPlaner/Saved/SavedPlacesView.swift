import SwiftData
import SwiftUI

struct SavedPlacesView: View {
    @Query(sort: \PersistedSavedPlace.savedAt, order: .reverse) private var savedPlaces: [PersistedSavedPlace]

    var body: some View {
        NavigationStack {
            Group {
                if savedPlaces.isEmpty {
                    ContentUnavailableView("No Saved Places", systemImage: "bookmark", description: Text("Bookmark a discovery to keep it available offline."))
                } else {
                    List(savedPlaces, id: \.placeID) { saved in
                        if let place = saved.place {
                            NavigationLink {
                                PlaceDetailView(place: place)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name).font(.headline)
                                    Text(place.editorialReason).font(.subheadline).foregroundStyle(.secondary)
                                    Text("Saved \(saved.savedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .navigationTitle("Saved Places")
        }
    }
}

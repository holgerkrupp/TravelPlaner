import MapKit
import SwiftData
import SwiftUI

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: PersistedTrip
    @State private var destinationQuery = ""
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        List {
            Section("Stops") {
                if trip.stops.isEmpty {
                    ContentUnavailableView("No Stops", systemImage: "mappin", description: Text("Search for a destination below."))
                } else {
                    ForEach(trip.stops) { stop in
                        VStack(alignment: .leading) {
                            Text("\(stop.order + 1). \(stop.name)").font(.headline)
                            Text("\(stop.coordinate.latitude.formatted(.number.precision(.fractionLength(3)))), \(stop.coordinate.longitude.formatted(.number.precision(.fractionLength(3))))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        trip.stops.remove(atOffsets: offsets)
                        normalizeOrders()
                    }
                }
            }
            Section("Add destination") {
                TextField("City, landmark, or address", text: $destinationQuery)
                    .textInputAutocapitalization(.words)
                Button {
                    Task { await searchDestination() }
                } label: {
                    Label(isSearching ? "Searching…" : "Add destination", systemImage: "magnifyingglass")
                }
                .disabled(destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                if let searchError { Text(searchError).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle(trip.name)
    }

    private func searchDestination() async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destinationQuery
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                searchError = "No destination found."
                return
            }
            let location = item.location
            let coordinate = try GeoCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            let stop = TripStop(name: item.name ?? destinationQuery, coordinate: coordinate, order: trip.stops.count)
            trip.stops.append(stop)
            trip.destinations.append(stop.name)
            try? modelContext.save()
            destinationQuery = ""
        } catch {
            searchError = "Destination search is unavailable right now."
        }
    }

    private func normalizeOrders() {
        trip.stops = trip.stops.enumerated().map { index, stop in
            TripStop(id: stop.id, name: stop.name, coordinate: stop.coordinate, order: index)
        }
        try? modelContext.save()
    }
}

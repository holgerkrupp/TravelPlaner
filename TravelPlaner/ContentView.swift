import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingNewTrip = false
    @State private var newTripName = ""
    @Query(sort: \PersistedTrip.name) private var storedTrips: [PersistedTrip]

    var body: some View {
        TabView {
            tripsView.tabItem { Label("Trips", systemImage: "airplane") }
            DiscoverView().tabItem { Label("Discover", systemImage: "map") }
        }
    }

    private var tripsView: some View {
        NavigationStack {
            Group {
                if storedTrips.isEmpty {
                    ContentUnavailableView("No Trips Yet", systemImage: "airplane", description: Text("Create a trip to start planning."))
                } else {
                    List(storedTrips, id: \.id) { storedTrip in
                        NavigationLink {
                            TripDetailView(trip: storedTrip)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(storedTrip.name).font(.headline)
                                if !storedTrip.destinations.isEmpty {
                                    Text(storedTrip.destinations.joined(separator: " • "))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                Button { showingNewTrip = true } label: { Label("New Trip", systemImage: "plus") }
            }
            .sheet(isPresented: $showingNewTrip) {
                NavigationStack {
                    Form { TextField("Trip name", text: $newTripName) }
                        .navigationTitle("New Trip")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingNewTrip = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Create") {
                                    let name = newTripName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !name.isEmpty else { return }
                                    modelContext.insert(PersistedTrip(Trip(name: name)))
                                    try? modelContext.save()
                                    newTripName = ""
                                    showingNewTrip = false
                                }
                            }
                        }
                }
            }
        }
    }
}

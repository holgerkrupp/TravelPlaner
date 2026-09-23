import SwiftUI

struct ContentView: View {
    @StateObject private var store = TripStore()

    var body: some View {
        NavigationStack {
            Group {
                if store.trips.isEmpty {
                    ContentUnavailableView(
                        "No Trips Yet",
                        systemImage: "airplane",
                        description: Text("Create a trip to start planning.")
                    )
                } else {
                    List(store.trips) { trip in
                        VStack(alignment: .leading) {
                            Text(trip.name).font(.headline)
                            if !trip.destinations.isEmpty {
                                Text(trip.destinations.joined(separator: " • "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
        }
    }
}

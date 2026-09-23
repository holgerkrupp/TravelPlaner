import MapKit
import SwiftData
import SwiftUI

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: PersistedTrip
    @State private var destinationQuery = ""
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var routes: [MKRoute] = []
    @State private var camera: MapCameraPosition = .automatic
    @State private var detours: [DetourCandidate] = []
    @State private var isDiscovering = false
    @State private var detourMessage: String?
    @State private var companionEnabled = false
    private let companion = TravelCompanion()
    private let notifier = LocalHintNotifier()

    var body: some View {
        List {
            if !trip.stops.isEmpty {
                Section("Route") {
                    Map(position: $camera) {
                        ForEach(trip.stops) { stop in
                            Marker(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude))
                        }
                        ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                            MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
                        }
                    }
                    .frame(minHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .task(id: trip.stops.map(\.id)) { await calculateRoute() }
                    if !routes.isEmpty {
                        let distance = routes.reduce(0) { $0 + $1.distance }
                        let travelTime = routes.reduce(0) { $0 + $1.expectedTravelTime }
                        Text("\(distance / 1000, specifier: "%.1f") km · \(travelTime / 60, specifier: "%.0f") min")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
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
            if trip.stops.count >= 2 {
                Section("Travel companion") {
                    Toggle("Nearby worthwhile hints", isOn: $companionEnabled)
                        .onChange(of: companionEnabled) { _, enabled in
                            guard enabled else { return }
                            Task { _ = try? await notifier.requestAuthorization() }
                        }
                    Text("Notifications are opt-in, throttled, and limited to exceptional discoveries. TravelPlaner does not start continuous tracking here.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Worth a detour") {
                    Button {
                        Task { await discoverDetours() }
                    } label: {
                        Label(isDiscovering ? "Searching route corridor…" : "Find worthwhile detours", systemImage: "sparkles.magnifyingglass")
                    }
                    .disabled(isDiscovering)
                    ForEach(detours) { detour in
                        VStack(alignment: .leading) {
                            Text(detour.place.name).font(.headline)
                            Text(detour.place.editorialReason).font(.subheadline)
                            if let route = detour.approximateDetour {
                                Text("Approx. \(route.expectedTravelTime / 60, specifier: "%.0f") min extra detour")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Add to trip") { addDetour(detour) }
                                .buttonStyle(.bordered)
                        }
                    }
                    if let detourMessage { Text(detourMessage).font(.caption).foregroundStyle(.secondary) }
                }
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

    private func addDetour(_ detour: DetourCandidate) {
        guard !trip.stops.contains(where: { $0.coordinate == detour.place.coordinate }) else { return }
        let stop = TripStop(
            name: detour.place.name,
            coordinate: detour.place.coordinate,
            order: trip.stops.count
        )
        trip.stops.append(stop)
        trip.destinations.append(stop.name)
        try? modelContext.save()
    }

    private func calculateRoute() async {
        guard trip.stops.count >= 2 else { routes = []; return }
        do {
            var calculated: [MKRoute] = []
            for pair in zip(trip.stops, trip.stops.dropFirst()) {
                let request = MKDirections.Request()
                request.source = MKMapItem(location: CLLocation(latitude: pair.0.coordinate.latitude, longitude: pair.0.coordinate.longitude), address: nil)
                request.destination = MKMapItem(location: CLLocation(latitude: pair.1.coordinate.latitude, longitude: pair.1.coordinate.longitude), address: nil)
                request.transportType = .automobile
                guard let segment = try await MKDirections(request: request).calculate().routes.first else { throw AppServiceError.routeUnavailable }
                calculated.append(segment)
            }
            routes = calculated
        } catch {
            routes = []
        }
    }

    @MainActor
    private func discoverDetours() async {
        isDiscovering = true
        detourMessage = nil
        defer { isDiscovering = false }
        let coordinator = TripDiscoveryCoordinator(
            discovery: DiscoveryPipeline(cloudKit: PublicCloudKitService(), adapters: [WikidataGeoSearchAdapter(), OpenStreetMapOverpassAdapter()], evaluator: CoverageEvaluator(policy: CoveragePolicy())),
            route: MapKitRouteService(),
            ranker: DiscoveryRanker()
        )
        do {
            detours = try await coordinator.discover(for: trip.value)
            if detours.isEmpty { detourMessage = "No worthwhile discoveries were found in this corridor." }
            if companionEnabled, let top = detours.first,
               let hint = await companion.eligibleHint(for: top.place, score: top.score) {
                try? await notifier.schedule(hint)
            }
        } catch {
            detourMessage = "Route discovery is unavailable right now; cached trip data remains available."
        }
    }
}

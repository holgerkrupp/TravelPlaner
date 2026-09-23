import MapKit
import SwiftUI
import SwiftData

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var interestSelections: [PersistedInterestSelection]
    @State private var places = SamplePlaces.all
    @State private var selectedPlaceID: UUID?
    @State private var camera: MapCameraPosition = .automatic
    @State private var showingSuggestion = false
    @State private var isLocating = false
    @State private var locationMessage: String?
    @State private var selectedCategory: PlaceCategory?
    @State private var hasMapAppeared = false
    @State private var visibleDiscoveryTask: Task<Void, Never>?
    private let locationService = CoreLocationService()
    private let discoveryCoordinator: DiscoveryRequestCoordinator

    private var rankedPlaces: [Place] {
        let selected = interestSelections.first?.interests ?? []
        let ranker = DiscoveryRanker()
        let scored = ranker.rank(places.map { place in
            let matching = place.interests.intersection(selected).count
            let uniqueness = place.kind == .majorDestination || place.kind == .remoteDestination ? 0.85 : 0.65
            return (place, RankingInputs(
                baseNotability: place.baseNotability,
                uniqueness: uniqueness,
                sourceConfidence: place.sources.isEmpty ? 0 : 1,
                matchingInterestCount: matching,
                selectedInterestCount: selected.count
            ))
        })
        return scored.map(\.0)
    }

    private var displayedPlaces: [Place] {
        guard let selectedCategory else { return rankedPlaces }
        return rankedPlaces.filter { $0.category == selectedCategory }
    }

    init() {
        let pipeline = DiscoveryPipeline(
            cloudKit: PublicCloudKitService(),
            adapters: [WikidataGeoSearchAdapter(), OpenStreetMapOverpassAdapter()],
            evaluator: CoverageEvaluator(policy: CoveragePolicy())
        )
        discoveryCoordinator = DiscoveryRequestCoordinator(pipeline: pipeline)
    }

    var body: some View {
        NavigationSplitView {
            List(displayedPlaces, id: \.id, selection: $selectedPlaceID) { place in
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(.headline)
                    Text(place.editorialReason).font(.subheadline).foregroundStyle(.secondary)
                    Label(place.category.rawValue.capitalized, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(place.name), \(place.editorialReason)")
            }
            .navigationTitle("Discover")
            .toolbar {
                Button { showingSuggestion = true } label: { Label("Suggest a place", systemImage: "plus.bubble") }
                Menu {
                    Button("All categories") { selectedCategory = nil }
                    ForEach(PlaceCategory.allCases, id: \.self) { category in
                        Button(category.rawValue.capitalized) { selectedCategory = category }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                Button {
                    Task { await centerOnCurrentLocation() }
                } label: {
                    Label(isLocating ? "Locating…" : "Near me", systemImage: "location")
                }
                .disabled(isLocating)
            }
            .sheet(isPresented: $showingSuggestion) {
                SuggestionFormView(coordinator: SuggestionCoordinator(cloud: CloudKitSuggestionService(), offlineQueue: appState.offlineWriteQueue))
            }
        } detail: {
            Map(position: $camera, selection: $selectedPlaceID) {
                ForEach(displayedPlaces, id: \.id) { place in
                    Marker(place.name, coordinate: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                        .tag(place.id)
                }
            }
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .onEnd) { context in
                guard hasMapAppeared else {
                    hasMapAppeared = true
                    return
                }
                scheduleVisibleDiscovery(for: context.region)
            }
            .overlay(alignment: .bottom) {
                if let selectedPlace = displayedPlaces.first(where: { $0.id == selectedPlaceID }) {
                    PlaceCard(place: selectedPlace)
                        .padding()
                }
                if let locationMessage {
                    Text(locationMessage)
                        .font(.caption)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Map")
        }
        .onDisappear { visibleDiscoveryTask?.cancel() }
    }

    @MainActor
    private func scheduleVisibleDiscovery(for region: MKCoordinateRegion) {
        visibleDiscoveryTask?.cancel()
        visibleDiscoveryTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(450))
                try Task.checkCancellation()
                let center = region.center
                let edge = CLLocationCoordinate2D(latitude: center.latitude + region.span.latitudeDelta / 2, longitude: center.longitude)
                let radius = CLLocation(latitude: center.latitude, longitude: center.longitude)
                    .distance(from: CLLocation(latitude: edge.latitude, longitude: edge.longitude))
                let request = DiscoveryRequest(center: center, radius: min(max(radius, 1_000), 100_000))
                let discovered = try await discoveryCoordinator.discover(for: request)
                guard !Task.isCancelled, !discovered.isEmpty else { return }
                places = discovered
                SwiftDataPlaceSnapshotStore(context: modelContext).store(discovered, context: "visible")
            } catch is CancellationError {
                // A newer camera position superseded this request.
            } catch {
                // Keep current contents when a visible-region refresh fails.
            }
        }
    }

    @MainActor
    private func centerOnCurrentLocation() async {
        isLocating = true
        locationMessage = nil
        defer { isLocating = false }
        do {
            let location = try await locationService.currentLocation()
            camera = .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 10_000, longitudinalMeters: 10_000))
            let discovered = try await discoveryCoordinator.discover(for: DiscoveryRequest(center: location.coordinate, radius: 10_000))
            if !discovered.isEmpty {
                places = discovered
                SwiftDataPlaceSnapshotStore(context: modelContext).store(discovered, context: "nearby")
            } else if let cached = SwiftDataPlaceSnapshotStore(context: modelContext).load(context: "nearby") {
                places = cached.places
                locationMessage = "Showing cached discoveries from \(cached.cachedAt.formatted(date: .abbreviated, time: .shortened))."
            }
        } catch {
            if let cached = SwiftDataPlaceSnapshotStore(context: modelContext).load(context: "nearby") {
                places = cached.places
                locationMessage = "Showing cached discoveries from \(cached.cachedAt.formatted(date: .abbreviated, time: .shortened))."
            } else {
                locationMessage = "Location or network is unavailable. You can still browse the bundled discoveries."
            }
        }
    }
}

private struct PlaceCard: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(place.name).font(.headline)
            Text(place.editorialReason).font(.subheadline)
            Text("Source: \(place.sources.first?.source.rawValue.capitalized ?? "Unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)
            NavigationLink("View details", destination: PlaceDetailView(place: place))
                .font(.subheadline.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }
}

enum SamplePlaces {
    static let all: [Place] = [
        try! Place(
            id: UUID(uuidString: "D8AFD6EF-887E-40FA-B0B2-3D4B28D0A001")!,
            name: "Marble Caves",
            alternateNames: ["Capillas de Mármol"],
            coordinate: try! GeoCoordinate(latitude: -46.651, longitude: -72.627),
            category: .geology,
            interests: [.nature, .geology, .unusual],
            kind: .remoteDestination,
            editorialReason: "A rare, wave-carved marble shoreline worth the journey.",
            sources: [try! PlaceSourceReference(source: .wikidata, externalID: "Q675745")],
            estimatedVisitDurationMinutes: 120,
            baseNotability: 0.92
        ),
        try! Place(
            id: UUID(uuidString: "D8AFD6EF-887E-40FA-B0B2-3D4B28D0A002")!,
            name: "Taylor Glacier",
            coordinate: try! GeoCoordinate(latitude: -77.75, longitude: 162.25),
            category: .nature,
            interests: [.nature, .science, .unusual],
            kind: .remoteDestination,
            editorialReason: "A vividly colored Antarctic glacier with an extraordinary outflow.",
            sources: [try! PlaceSourceReference(source: .wikidata, externalID: "Q769618")],
            estimatedVisitDurationMinutes: 90,
            baseNotability: 0.88
        )
    ]
}

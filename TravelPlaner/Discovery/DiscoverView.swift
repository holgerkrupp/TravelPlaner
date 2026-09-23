import MapKit
import SwiftUI

struct DiscoverView: View {
    @State private var places = SamplePlaces.all
    @State private var selectedPlaceID: UUID?
    @State private var camera: MapCameraPosition = .automatic
    @State private var showingSuggestion = false
    @State private var isLocating = false
    @State private var locationMessage: String?
    private let locationService = CoreLocationService()
    private let discoveryService = DiscoveryPipeline(
        cloudKit: PublicCloudKitService(),
        adapters: [WikidataGeoSearchAdapter(), OpenStreetMapOverpassAdapter()],
        evaluator: CoverageEvaluator(policy: CoveragePolicy())
    )

    var body: some View {
        NavigationSplitView {
            List(places, id: \.id, selection: $selectedPlaceID) { place in
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
                Button {
                    Task { await centerOnCurrentLocation() }
                } label: {
                    Label(isLocating ? "Locating…" : "Near me", systemImage: "location")
                }
                .disabled(isLocating)
            }
            .sheet(isPresented: $showingSuggestion) {
                SuggestionFormView(coordinator: SuggestionCoordinator(cloud: CloudKitSuggestionService()))
            }
        } detail: {
            Map(position: $camera, selection: $selectedPlaceID) {
                ForEach(places, id: \.id) { place in
                    Marker(place.name, coordinate: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                        .tag(place.id)
                }
            }
            .mapStyle(.standard)
            .overlay(alignment: .bottom) {
                if let selectedPlace = places.first(where: { $0.id == selectedPlaceID }) {
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
    }

    @MainActor
    private func centerOnCurrentLocation() async {
        isLocating = true
        locationMessage = nil
        defer { isLocating = false }
        do {
            let location = try await locationService.currentLocation()
            camera = .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 10_000, longitudinalMeters: 10_000))
            let discovered = try await discoveryService.discover(for: DiscoveryRequest(center: location.coordinate, radius: 10_000))
            if !discovered.isEmpty { places = discovered }
        } catch {
            locationMessage = "Location is unavailable. You can still browse cached discoveries."
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

import Foundation
import CoreLocation
import CloudKit
import MapKit
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
    @State private var voteMessage: String?
    @State private var aggregate: VoteAggregate?
    @State private var isVoting = false
    @State private var imageAsset: PlaceImageAsset?
    @State private var appleEnrichment: ApplePlaceEnrichment?

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
            if let imageAsset {
                Section("Image") {
                    AsyncImage(url: imageAsset.remoteURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        case .failure: Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                        default: ProgressView()
                        }
                    }
                    Text("\(imageAsset.attribution) · \(imageAsset.license)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let appleEnrichment {
                Section("Current map information") {
                    Text(appleEnrichment.name)
                    if let address = appleEnrichment.address { Text(address).font(.caption).foregroundStyle(.secondary) }
                    if let phone = appleEnrichment.phoneNumber { Text(phone).font(.caption) }
                    Button("Open in Maps") { openInMaps() }
                }
            } else {
                Section("Map") { Button("Look up current Apple Maps information") { Task { await enrichFromAppleMaps() } } }
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
            Section("Was it worth visiting?") {
                Text("Voting is enabled only after this device verifies that you are at the place. Precise location is never uploaded.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button { Task { await vote(.worthVisiting) } } label: {
                        Label("Worth it", systemImage: "hand.thumbsup")
                    }
                    .disabled(isVoting)
                    Button { Task { await vote(.notWorthVisiting) } } label: {
                        Label("Not worth it", systemImage: "hand.thumbsdown")
                    }
                    .disabled(isVoting)
                }
                if let aggregate {
                    Text(aggregate.isInformative ? "Community signal: \(aggregate.confidenceScore, specifier: "%.0f")% positive from \(aggregate.totalCount) votes." : "Not enough votes for a reliable community signal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let voteMessage { Text(voteMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(place.name)
        .task {
            imageAsset = try? await WikimediaCommonsImageService().image(for: place)
        }
    }

    @MainActor
    private func enrichFromAppleMaps() async {
        appleEnrichment = try? await ApplePlaceEnrichmentService().lookup(place: place)
    }

    private func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude), address: nil)
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    @MainActor
    private func vote(_ value: VoteValue) async {
        isVoting = true
        voteMessage = nil
        defer { isVoting = false }
        do {
            let location = try await CoreLocationService().currentLocation()
            guard let evidence = VisitEligibilityEvaluator(policy: VisitEligibilityPolicy()).evaluate(place: place, location: location) else {
                voteMessage = "You must be close enough to the place for a recent, accurate location fix."
                return
            }
            let cloud = try await CloudKitVoteService.forCurrentUser()
            let vote = PlaceVote(id: UUID(), placeID: place.id, value: value, verification: .currentProximity, coarseVisitMonth: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: evidence.observedAt)), updatedAt: .now)
            try await VoteCoordinator(cloud: cloud).submit(vote, eligibility: VisitEligibility(isEligible: true, reason: "Verified proximity"))
            aggregate = await VoteCoordinator(cloud: cloud).aggregate(for: place.id)
            voteMessage = "Your vote was saved."
        } catch {
            voteMessage = "Voting is unavailable without an authenticated iCloud account."
        }
    }
}

import CoreLocation
import Foundation
import UserNotifications

struct TravelHint: Equatable, Sendable {
    let placeID: UUID
    let title: String
    let body: String
    let score: Double
}

actor TravelCompanion {
    private var lastHintAt: Date?
    private var hintedPlaceIDs: Set<UUID> = []
    private let minimumInterval: TimeInterval
    private let maximumHintsPerDay: Int
    private var hintDay: Date?
    private var hintsToday = 0

    init(minimumInterval: TimeInterval = 60 * 30, maximumHintsPerDay: Int = 3) {
        self.minimumInterval = minimumInterval
        self.maximumHintsPerDay = max(1, maximumHintsPerDay)
    }

    func eligibleHint(for place: Place, score: DiscoveryScore, now: Date = .now) -> TravelHint? {
        let day = Calendar.current.startOfDay(for: now)
        if hintDay != day {
            hintDay = day
            hintsToday = 0
        }
        guard hintsToday < maximumHintsPerDay,
              score.total >= 0.65, !hintedPlaceIDs.contains(place.id),
              lastHintAt.map({ now.timeIntervalSince($0) >= minimumInterval }) ?? true else { return nil }
        lastHintAt = now
        hintedPlaceIDs.insert(place.id)
        hintsToday += 1
        return TravelHint(placeID: place.id, title: "Worth a small detour", body: "\(place.name) — \(place.editorialReason)", score: score.total)
    }

    func resetForNewTrip() {
        lastHintAt = nil
        hintedPlaceIDs.removeAll()
        hintDay = nil
        hintsToday = 0
    }
}

struct LocalHintNotifier: Sendable {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func schedule(_ hint: TravelHint) async throws {
        let content = UNMutableNotificationContent()
        content.title = hint.title
        content.body = hint.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: hint.placeID.uuidString, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}

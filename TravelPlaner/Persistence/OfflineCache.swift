import Foundation

struct CachedPlaceSet: Codable, Equatable, Sendable {
    let places: [Place]
    let cachedAt: Date
    let context: String
}

actor OfflinePlaceCache {
    private var sets: [String: CachedPlaceSet] = [:]
    private var pendingWrites: [String] = []

    func store(_ places: [Place], context: String, now: Date = .now) {
        sets[context] = CachedPlaceSet(places: PlaceDeduplicator.unique(places), cachedAt: now, context: context)
    }

    func load(context: String) -> CachedPlaceSet? { sets[context] }
    func enqueueWrite(_ key: String) { if !pendingWrites.contains(key) { pendingWrites.append(key) } }
    func pendingWriteKeys() -> [String] { pendingWrites }
    func markWriteComplete(_ key: String) { pendingWrites.removeAll { $0 == key } }
}

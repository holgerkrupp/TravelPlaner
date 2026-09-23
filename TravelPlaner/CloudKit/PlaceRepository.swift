import CloudKit
import Foundation

struct CloudKitPlaceRecordMapper: Sendable {
    static let recordType = "Place"

    static func recordID(for place: Place) -> CKRecord.ID {
        let key = place.sources.map(\.canonicalKey).sorted().first ?? place.id.uuidString
        let safe = key.unicodeScalars.map { scalar in
            let isASCIIAlphaNumeric = scalar.value >= 48 && scalar.value <= 57 || scalar.value >= 65 && scalar.value <= 90 || scalar.value >= 97 && scalar.value <= 122
            return isASCIIAlphaNumeric || scalar == "-" || scalar == "_" || scalar == "." ? String(scalar) : "_"
        }.joined()
        return CKRecord.ID(recordName: "place_\(safe)")
    }

    static func makeRecord(from place: Place) throws -> CKRecord {
        guard let source = place.sources.sorted(by: { $0.canonicalKey < $1.canonicalKey }).first else { throw MappingError.missingSource }
        let record = CKRecord(recordType: recordType, recordID: recordID(for: place))
        record["stableID"] = place.id.uuidString as NSString
        record["name"] = place.name as NSString
        record["alternateNames"] = place.alternateNames as NSArray
        record["latitude"] = place.coordinate.latitude as NSNumber
        record["longitude"] = place.coordinate.longitude as NSNumber
        record["category"] = place.category.rawValue as NSString
        record["kind"] = place.kind.rawValue as NSString
        record["editorialReason"] = place.editorialReason as NSString
        record["source"] = source.source.rawValue as NSString
        record["externalID"] = source.externalID as NSString
        record["sourceURL"] = source.sourceURL?.absoluteString as NSString?
        record["license"] = source.license as NSString?
        record["attribution"] = source.attribution as NSString?
        record["sourceUpdatedAt"] = source.sourceUpdatedAt as NSDate?
        record["discoveryVersion"] = source.discoveryVersion as NSString?
        record["interests"] = place.interests.map(\.rawValue) as NSArray
        record["baseNotability"] = place.baseNotability as NSNumber
        record["estimatedVisitMinutes"] = place.estimatedVisitDurationMinutes as NSNumber?
        record["boundingRadiusMeters"] = place.boundingRadiusMeters as NSNumber?
        return record
    }

    static func makePlace(from record: CKRecord) throws -> Place {
        guard let name = record["name"] as? String,
              let latitude = record["latitude"] as? NSNumber,
              let longitude = record["longitude"] as? NSNumber,
              let categoryRaw = record["category"] as? String,
              let category = PlaceCategory(rawValue: categoryRaw),
              let kindRaw = record["kind"] as? String,
              let kind = PlaceKind(rawValue: kindRaw),
              let reason = record["editorialReason"] as? String,
              let sourceRaw = record["source"] as? String,
              let source = PlaceSource(rawValue: sourceRaw),
              let externalID = record["externalID"] as? String else { throw MappingError.invalidRecord }
        let coordinate = try GeoCoordinate(latitude: latitude.doubleValue, longitude: longitude.doubleValue)
        let reference = try PlaceSourceReference(
            source: source,
            externalID: externalID,
            sourceURL: (record["sourceURL"] as? String).flatMap(URL.init(string:)),
            license: record["license"] as? String,
            attribution: record["attribution"] as? String,
            sourceUpdatedAt: record["sourceUpdatedAt"] as? Date,
            discoveryVersion: record["discoveryVersion"] as? String
        )
        let id = (record["stableID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let aliases = record["alternateNames"] as? [String] ?? []
        let interests = Set((record["interests"] as? [String] ?? []).compactMap(PlaceInterest.init(rawValue:)))
        return try Place(
            id: id,
            name: name,
            alternateNames: aliases,
            coordinate: coordinate,
            boundingRadiusMeters: (record["boundingRadiusMeters"] as? NSNumber)?.doubleValue,
            category: category,
            interests: interests,
            kind: kind,
            editorialReason: reason,
            sources: [reference],
            estimatedVisitDurationMinutes: (record["estimatedVisitMinutes"] as? NSNumber)?.intValue,
            baseNotability: (record["baseNotability"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    enum MappingError: Error { case missingSource, invalidRecord }
}

actor PlaceRepository {
    private let service: any CloudKitService
    private var cache: [String: [Place]] = [:]

    init(service: any CloudKitService) { self.service = service }

    func places(in region: CoverageRegion) async throws -> [Place] {
        let key = "\(region.center.latitude):\(region.center.longitude):\(region.radius)"
        if let cached = cache[key] { return cached }
        let places = try await service.fetchPlaces(in: region)
        cache[key] = PlaceDeduplicator.unique(places)
        return cache[key] ?? []
    }

    func place(id: UUID) async throws -> Place? {
        if let cached = cache.values.lazy.compactMap({ $0.first(where: { $0.id == id }) }).first { return cached }
        return try await service.fetchPlace(stableID: id)
    }

    func invalidate() { cache.removeAll() }
}

import CoreLocation
import Foundation

enum OpenDataAdapterError: Error { case invalidResponse, invalidPayload, unsupportedRegion }

private enum OpenDataNetwork {
    static func fetch(_ request: URLRequest, using session: URLSession, attempts: Int = 3) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        for attempt in 0..<max(1, attempts) {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw OpenDataAdapterError.invalidResponse }
                if (http.statusCode == 429 || (500...599).contains(http.statusCode)) && attempt + 1 < attempts {
                    try await backoff(attempt: attempt)
                    continue
                }
                return (data, http)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt + 1 < attempts { try await backoff(attempt: attempt) }
            }
        }
        throw lastError ?? OpenDataAdapterError.invalidResponse
    }

    private static func backoff(attempt: Int) async throws {
        try Task.checkCancellation()
        let delay = UInt64(250_000_000) * UInt64(1 << min(attempt, 2))
        try await Task.sleep(nanoseconds: delay)
    }
}

private struct WikidataGeoSearchResponse: Decodable {
    struct Query: Decodable {
        struct Page: Decodable {
            let pageid: Int
            let title: String
            let lat: Double
            let lon: Double
        }
        let geosearch: [Page]
    }
    let query: Query
}

struct WikidataGeoSearchAdapter: PlaceSourceAdapter {
    let source: PlaceSource = .wikidata
    let session: URLSession
    let endpoint: URL
    let limit: Int

    init(session: URLSession = .shared, endpoint: URL = URL(string: "https://www.wikidata.org/w/api.php")!, limit: Int = 50) {
        self.session = session
        self.endpoint = endpoint
        self.limit = min(max(limit, 1), 50)
    }

    func discover(in region: CoverageRegion) async throws -> [PlaceCandidate] {
        guard region.radius > 0, region.radius <= 100_000 else { throw OpenDataAdapterError.unsupportedRegion }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "geosearch"),
            URLQueryItem(name: "gscoord", value: "\(region.center.latitude)|\(region.center.longitude)"),
            URLQueryItem(name: "gsradius", value: String(Int(region.radius))),
            URLQueryItem(name: "gslimit", value: String(limit)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*")
        ]
        guard let url = components?.url else { throw OpenDataAdapterError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("TravelPlaner/1.0 (on-device discovery)", forHTTPHeaderField: "User-Agent")
        try Task.checkCancellation()
        let (data, response) = try await OpenDataNetwork.fetch(request, using: session)
        guard 200..<300 ~= response.statusCode else { throw OpenDataAdapterError.invalidResponse }
        let payload = try JSONDecoder().decode(WikidataGeoSearchResponse.self, from: data)
        return try payload.query.geosearch.map { item in
            let reference = try PlaceSourceReference(
                source: .wikidata,
                externalID: "page:\(item.pageid)",
                sourceURL: URL(string: "https://www.wikidata.org/wiki/Special:EntityData/Q\(item.pageid)"),
                license: "CC0",
                attribution: "Wikidata"
            )
            let place = try Place(
                name: item.title.replacingOccurrences(of: "_", with: " "),
                coordinate: try GeoCoordinate(latitude: item.lat, longitude: item.lon),
                category: .other,
                kind: .detourStop,
                editorialReason: "A nearby place identified through open geographic data.",
                sources: [reference]
            )
            return PlaceCandidate(place: place, discoveredAt: .now, canRepublish: true)
        }
    }
}

private struct OverpassResponse: Decodable {
    struct Element: Decodable {
        let type: String
        let id: Int
        let lat: Double?
        let lon: Double?
        let center: Center?
        let tags: [String: String]?
        struct Center: Decodable { let lat: Double; let lon: Double }
    }
    let elements: [Element]
}

struct OpenStreetMapOverpassAdapter: PlaceSourceAdapter {
    let source: PlaceSource = .openStreetMap
    let session: URLSession
    let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL = URL(string: "https://overpass-api.de/api/interpreter")!) {
        self.session = session
        self.endpoint = endpoint
    }

    func discover(in region: CoverageRegion) async throws -> [PlaceCandidate] {
        guard region.radius > 0, region.radius <= 50_000 else { throw OpenDataAdapterError.unsupportedRegion }
        let query = "[out:json][timeout:20];(nwr(around:\(Int(region.radius)),\(region.center.latitude),\(region.center.longitude))[tourism];nwr(around:\(Int(region.radius)),\(region.center.latitude),\(region.center.longitude))[historic];nwr(around:\(Int(region.radius)),\(region.center.latitude),\(region.center.longitude))[natural];);out center tags;"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = query.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("TravelPlaner/1.0 (on-device discovery)", forHTTPHeaderField: "User-Agent")
        try Task.checkCancellation()
        let (data, response) = try await OpenDataNetwork.fetch(request, using: session)
        guard 200..<300 ~= response.statusCode else { throw OpenDataAdapterError.invalidResponse }
        let payload = try JSONDecoder().decode(OverpassResponse.self, from: data)
        return try payload.elements.compactMap { element in
            guard let name = element.tags?["name"], !name.isEmpty else { return nil }
            let coordinate = element.center ?? OverpassResponse.Element.Center(lat: element.lat ?? 0, lon: element.lon ?? 0)
            guard (-90...90).contains(coordinate.lat), (-180...180).contains(coordinate.lon) else { return nil }
            let reference = try PlaceSourceReference(
                source: .openStreetMap,
                externalID: "\(element.type):\(element.id)",
                sourceURL: URL(string: "https://www.openstreetmap.org/\(element.type)/\(element.id)"),
                license: "ODbL 1.0",
                attribution: "© OpenStreetMap contributors"
            )
            let category: PlaceCategory = element.tags?["natural"] != nil ? .nature : element.tags?["historic"] != nil ? .history : .other
            let place = try Place(name: name, coordinate: try GeoCoordinate(latitude: coordinate.lat, longitude: coordinate.lon), category: category, editorialReason: "A nearby place identified through OpenStreetMap.", sources: [reference])
            return PlaceCandidate(place: place, discoveredAt: .now, canRepublish: true)
        }
    }
}

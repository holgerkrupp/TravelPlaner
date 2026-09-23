import Foundation
import MapKit

struct ApplePlaceEnrichment: Equatable, Sendable {
    let name: String
    let address: String?
    let phoneNumber: String?
    let url: URL?
}

struct ApplePlaceEnrichmentService: Sendable {
    func lookup(place: Place) async throws -> ApplePlaceEnrichment? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place.name
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
            latitudinalMeters: 2_000,
            longitudinalMeters: 2_000
        )
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { return nil }
        let address = item.address?.fullAddress ?? item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
        return ApplePlaceEnrichment(name: item.name ?? place.name, address: address, phoneNumber: item.phoneNumber, url: item.url)
    }
}

struct WikimediaCommonsImageService: Sendable {
    private let session: URLSession
    private let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL = URL(string: "https://commons.wikimedia.org/w/api.php")!) {
        self.session = session
        self.endpoint = endpoint
    }

    func image(for place: Place) async throws -> PlaceImageAsset? {
        guard let source = place.sources.first(where: { $0.source == .wikimediaCommons }) else { return nil }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: source.externalID.hasPrefix("File:") ? source.externalID : "File:\(source.externalID)"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "1200"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("TravelPlaner/1.0 (attribution-aware image lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard let info = payload.query.pages.values.first?.imageinfo.first,
              let imageURL = URL(string: info.thumburl ?? info.url) else { return nil }
        let metadata = info.extmetadata ?? [:]
        let license = metadata["LicenseShortName"]?.value ?? source.license ?? "License information unavailable"
        let attribution = metadata["Artist"]?.value ?? metadata["Credit"]?.value ?? source.attribution ?? "Wikimedia Commons"
        return PlaceImageAsset(id: UUID(), remoteURL: imageURL, license: license, attribution: attribution, sourceURL: source.sourceURL)
    }

    private struct Response: Decodable {
        struct Page: Decodable {
            struct ImageInfo: Decodable {
                let url: String
                let thumburl: String?
                let extmetadata: [String: Metadata]?
            }
            let imageinfo: [ImageInfo]
        }
        struct Query: Decodable { let pages: [String: Page] }
        let query: Query
    }

    private struct Metadata: Decodable { let value: String? }
}

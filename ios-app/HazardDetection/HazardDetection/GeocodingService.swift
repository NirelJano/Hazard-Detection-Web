import CoreLocation
import Foundation

enum GeocodingError: LocalizedError {
    case missingConfig
    case invalidURL
    case requestFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingConfig: return "Mapbox configuration is missing in Info.plist."
        case .invalidURL: return "Invalid Mapbox endpoint URL."
        case .requestFailed(let message): return "Geocoding failed: \(message)"
        }
    }
}

actor GeocodingService {
    static let shared = GeocodingService()
    
    private let accessToken: String?
    
    private init() {
        self.accessToken = Bundle.main.object(forInfoDictionaryKey: "MapboxAccessToken") as? String
    }
    
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        guard let accessToken, !accessToken.isEmpty else {
            throw GeocodingError.missingConfig
        }
        
        let urlString = "https://api.mapbox.com/search/geocode/v6/reverse?longitude=\(coordinate.longitude)&latitude=\(coordinate.latitude)&access_token=\(accessToken)"
        
        guard let url = URL(string: urlString) else {
            throw GeocodingError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
            throw GeocodingError.requestFailed(message)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]],
              let firstFeature = features.first,
              let properties = firstFeature["properties"] as? [String: Any],
              let fullAddress = properties["full_address"] as? String else {
            throw GeocodingError.requestFailed("Failed to parse address from Mapbox response")
        }
        
        return fullAddress
    }
}

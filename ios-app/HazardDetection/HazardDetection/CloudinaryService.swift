import Foundation
import UIKit

enum CloudinaryError: LocalizedError {
    case missingConfig
    case invalidImage
    case invalidURL
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingConfig: return "Cloudinary configuration is missing in Info.plist."
        case .invalidImage: return "Failed to process image data."
        case .invalidURL: return "Invalid Cloudinary endpoint URL."
        case .uploadFailed(let message): return "Upload failed: \(message)"
        }
    }
}

actor CloudinaryService {
    static let shared = CloudinaryService()
    
    private let cloudName: String?
    private let uploadPreset: String?
    
    private init() {
        self.cloudName = Bundle.main.object(forInfoDictionaryKey: "CloudinaryCloudName") as? String
        self.uploadPreset = Bundle.main.object(forInfoDictionaryKey: "CloudinaryUploadPreset") as? String
    }
    
    var isConfigured: Bool {
        guard let cloudName, let uploadPreset,
              !cloudName.isEmpty, !uploadPreset.isEmpty,
              !cloudName.contains("$("), !uploadPreset.contains("$(") else {
            return false
        }
        return true
    }
    
    func uploadImage(_ image: UIImage) async throws -> String {
        guard isConfigured, let cloudName = cloudName, let uploadPreset = uploadPreset else {
            throw CloudinaryError.missingConfig
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw CloudinaryError.invalidImage
        }
        
        guard let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloudName)/image/upload") else {
            throw CloudinaryError.invalidURL
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add upload_preset
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"upload_preset\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(uploadPreset)\r\n".data(using: .utf8)!)
        
        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
            throw CloudinaryError.uploadFailed(message)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secureUrl = json["secure_url"] as? String else {
            throw CloudinaryError.uploadFailed("Failed to parse secure_url from response")
        }
        
        return secureUrl
    }
}

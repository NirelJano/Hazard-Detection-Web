import FirebaseFirestore
import Foundation

struct AppUser: Identifiable, Equatable {
    let id: String
    let email: String

    var displayName: String { email.isEmpty ? "User" : email }
}

struct AppUserProfile: Codable, Equatable {
    var type: String
    var email: String?
    var displayName: String?
}

struct HazardReport: Identifiable, Codable, Equatable {
    @DocumentID var docId: String?
    var numericId: Int?
    var hazardType: String
    var date: String
    var description: String?
    var coordinate: GeoPoint
    var address: String?
    var imageUrl: String?
    var status: String
    var reportedBy: String
    @ServerTimestamp var createdAt: Date?

    var id: String { docId ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case docId
        case numericId = "id"
        case hazardType
        case date
        case description
        case coordinate
        case address
        case imageUrl
        case status
        case reportedBy
        case createdAt
    }
}

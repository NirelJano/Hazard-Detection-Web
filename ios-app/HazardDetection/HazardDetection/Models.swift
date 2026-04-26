import CoreGraphics
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

struct HazardReport: Identifiable, Equatable {
    var docId: String?
    var numericId: Int?
    var hazardType: String
    var date: String
    var description: String?
    var coordinate: GeoPoint
    var address: String?
    var imageUrl: String?
    var status: String
    var reportedBy: String
    var createdAt: Int64?

    // Detection metadata
    var detectedLabel: String?
    var detectionConfidence: Double?
    var detectionSource: String?
    var detectionBoundingBox: DetectionBoundingBox?

    var id: String { docId ?? UUID().uuidString }

    init(
        docId: String?,
        numericId: Int?,
        hazardType: String,
        date: String,
        description: String?,
        coordinate: GeoPoint,
        address: String?,
        imageUrl: String?,
        status: String,
        reportedBy: String,
        createdAt: Int64?,
        detectedLabel: String?,
        detectionConfidence: Double?,
        detectionSource: String?,
        detectionBoundingBox: DetectionBoundingBox?
    ) {
        self.docId = docId
        self.numericId = numericId
        self.hazardType = hazardType
        self.date = date
        self.description = description
        self.coordinate = coordinate
        self.address = address
        self.imageUrl = imageUrl
        self.status = status
        self.reportedBy = reportedBy
        self.createdAt = createdAt
        self.detectedLabel = detectedLabel
        self.detectionConfidence = detectionConfidence
        self.detectionSource = detectionSource
        self.detectionBoundingBox = detectionBoundingBox
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard
            let hazardType = data["hazardType"] as? String,
            let date = data["date"] as? String,
            let coordinate = data["coordinate"] as? GeoPoint,
            let status = data["status"] as? String,
            let reportedBy = data["reportedBy"] as? String
        else { return nil }

        self.init(
            docId: document.documentID,
            numericId: Self.readInt(data["id"]),
            hazardType: hazardType,
            date: date,
            description: data["description"] as? String,
            coordinate: coordinate,
            address: data["address"] as? String,
            imageUrl: data["imageUrl"] as? String,
            status: status,
            reportedBy: reportedBy,
            createdAt: Self.readCreatedAt(data["createdAt"]),
            detectedLabel: data["detectedLabel"] as? String,
            detectionConfidence: data["detectionConfidence"] as? Double,
            detectionSource: data["detectionSource"] as? String,
            detectionBoundingBox: DetectionBoundingBox(dictionary: data["detectionBoundingBox"] as? [String: Any])
        )
    }

    private static func readCreatedAt(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? Timestamp {
            return Int64(value.dateValue().timeIntervalSince1970 * 1000)
        }
        return nil
    }

    private static func readInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Double { return Int(value) }
        return nil
    }
}

struct DetectionBoundingBox: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(from cgRect: CGRect) {
        self.x = Double(cgRect.origin.x)
        self.y = Double(cgRect.origin.y)
        self.width = Double(cgRect.size.width)
        self.height = Double(cgRect.size.height)
    }
    
    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        self.x = dictionary["x"] as? Double ?? 0
        self.y = dictionary["y"] as? Double ?? 0
        self.width = dictionary["width"] as? Double ?? 0
        self.height = dictionary["height"] as? Double ?? 0
    }

    var dictionary: [String: Double] {
        [
            "x": x,
            "y": y,
            "width": width,
            "height": height
        ]
    }
}

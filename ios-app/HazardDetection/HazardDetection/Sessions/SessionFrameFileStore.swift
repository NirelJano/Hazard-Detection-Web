import Foundation
import UIKit

struct SessionFrameFileStore {
    private static let baseDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("DetectionSessions", isDirectory: true)
    }()

    func sessionDirectory(for sessionId: UUID) -> URL {
        Self.baseDirectory.appendingPathComponent(sessionId.uuidString, isDirectory: true)
    }

    @discardableResult
    func saveFrame(
        _ image: UIImage,
        sessionId: UUID,
        candidateId: UUID,
        compressionQuality: CGFloat = 0.7
    ) throws -> String {
        let dir = sessionDirectory(for: sessionId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw FrameStoreError.compressionFailed
        }
        let fileName = "\(candidateId.uuidString).jpg"
        let fileURL = dir.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    func loadFrame(fileName: String, sessionId: UUID) throws -> UIImage {
        let fileURL = sessionDirectory(for: sessionId).appendingPathComponent(fileName)
        let data = try Data(contentsOf: fileURL)
        guard let image = UIImage(data: data) else {
            throw FrameStoreError.imageDecodingFailed
        }
        return image
    }

    func deleteFrame(fileName: String, sessionId: UUID) throws {
        let fileURL = sessionDirectory(for: sessionId).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func deleteSessionFrames(sessionId: UUID) throws {
        let dir = sessionDirectory(for: sessionId)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }
}

enum FrameStoreError: LocalizedError {
    case compressionFailed
    case imageDecodingFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed: return "Failed to compress frame image."
        case .imageDecodingFailed: return "Failed to decode stored frame image."
        }
    }
}

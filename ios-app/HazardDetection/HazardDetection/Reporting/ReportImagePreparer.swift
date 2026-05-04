import Foundation
import UIKit

struct PreparedReportImage {
    let data: Data
    let uiImage: UIImage
    let localURL: URL?
}

struct ReportImagePreparer {
    func prepareImage(for draft: ReportDraft) throws -> PreparedReportImage {
        let data: Data
        let localURL: URL?

        if let d = draft.imageData {
            data = d
            localURL = draft.imageLocalURL
        } else if let url = draft.imageLocalURL {
            data = try Data(contentsOf: url)
            localURL = url
        } else {
            throw ReportValidationError.missingImage
        }

        guard let uiImage = UIImage(data: data) else {
            throw ReportValidationError.invalidImageData
        }

        return PreparedReportImage(data: data, uiImage: uiImage, localURL: localURL)
    }
}

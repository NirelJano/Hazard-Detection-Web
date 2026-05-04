import Foundation
import UIKit

struct PreparedReportImage {
    let data: Data
    let localURL: URL?

    var uiImage: UIImage? { UIImage(data: data) }
}

struct ReportImagePreparer {
    func prepareImage(for draft: ReportDraft) throws -> PreparedReportImage {
        if let data = draft.imageData {
            return PreparedReportImage(data: data, localURL: draft.imageLocalURL)
        }
        if let url = draft.imageLocalURL {
            let data = try Data(contentsOf: url)
            return PreparedReportImage(data: data, localURL: url)
        }
        throw ReportValidationError.missingImage
    }
}

import CoreGraphics
import CoreImage
import Foundation
import UIKit

struct FrameQualityScore: Codable, Equatable {
    let brightness: Double
    let blurScore: Double
    let isTooDark: Bool
    let isBlurry: Bool
}

final class CameraConditionAnalyzer {
    private let minimumInterval: TimeInterval
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastAnalysisTime: Date = .distantPast
    private var lastScore: FrameQualityScore?

    init(minimumInterval: TimeInterval = 0.5) {
        self.minimumInterval = minimumInterval
    }

    func analyzeIfNeeded(image: UIImage?) -> FrameQualityScore? {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= minimumInterval else { return lastScore }
        lastAnalysisTime = now
        guard let image, let cgImage = image.cgImage else { return lastScore }
        lastScore = analyze(cgImage: cgImage)
        return lastScore
    }

    private func analyze(cgImage: CGImage) -> FrameQualityScore {
        let target = CGSize(width: 48, height: 36)
        let ciImage = CIImage(cgImage: cgImage)
        let scaled = ciImage.transformed(by: CGAffineTransform(
            scaleX: target.width / CGFloat(cgImage.width),
            y: target.height / CGFloat(cgImage.height)
        ))
        guard let small = context.createCGImage(scaled, from: CGRect(origin: .zero, size: target)),
              let provider = small.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data)
        else {
            return FrameQualityScore(brightness: 0.5, blurScore: 0.5, isTooDark: false, isBlurry: false)
        }

        let width = small.width
        let height = small.height
        let bytesPerPixel = max(1, small.bitsPerPixel / 8)
        let bytesPerRow = small.bytesPerRow
        var luminance = Array(repeating: 0.0, count: width * height)
        var total = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Double(bytes[offset]) / 255.0
                let g = bytesPerPixel > 1 ? Double(bytes[offset + 1]) / 255.0 : r
                let b = bytesPerPixel > 2 ? Double(bytes[offset + 2]) / 255.0 : r
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                luminance[y * width + x] = luma
                total += luma
            }
        }

        let brightness = total / Double(width * height)
        var edgeTotal = 0.0
        var edgeSamples = 0
        if width > 2, height > 2 {
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let center = luminance[y * width + x]
                    let horizontal = abs(center - luminance[y * width + x - 1]) + abs(center - luminance[y * width + x + 1])
                    let vertical = abs(center - luminance[(y - 1) * width + x]) + abs(center - luminance[(y + 1) * width + x])
                    edgeTotal += horizontal + vertical
                    edgeSamples += 4
                }
            }
        }

        // TODO: Replace this contrast proxy with a small Laplacian/sharpness kernel if needed.
        let blurScore = edgeSamples > 0 ? edgeTotal / Double(edgeSamples) : 0.5
        return FrameQualityScore(
            brightness: brightness,
            blurScore: blurScore,
            isTooDark: brightness < 0.18,
            isBlurry: blurScore < 0.018
        )
    }
}

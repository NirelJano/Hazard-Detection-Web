import Accelerate
import CoreImage
import UIKit

struct FrameQualityService {

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func evaluate(image: UIImage, motionStability: Float = 1.0) -> FrameQualityScores {
        let blur = laplacianVariance(image: image)
        let brightness = averageLuminance(image: image)
        let overexp = overexposureRatio(image: image)
        let contrast = contrastScore(brightness: brightness, overexposure: overexp)
        return FrameQualityScores(
            blurScore: blur,
            brightnessScore: brightness,
            overexposureRatio: overexp,
            contrastScore: contrast,
            motionStabilityScore: motionStability
        )
    }

    func qualityHint(scores: FrameQualityScores, motionStability: Float) -> QualityHint? {
        if scores.blurScore < 80 || motionStability < 0.4 { return .motionBlur }
        if scores.brightnessScore < 0.15 || scores.overexposureRatio > 0.30 { return .lowVisibility }
        if scores.blurScore < 120 { return .tapToFocus }
        return nil
    }

    // MARK: - Laplacian variance (blur detection)
    // Downsample to ≤200px, convert to grayscale, apply Laplacian kernel, measure variance.
    private func laplacianVariance(image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 100 }

        // Downsample
        let scale = min(1.0, 200.0 / max(CGFloat(cgImage.width), CGFloat(cgImage.height)))
        let w = max(1, Int(CGFloat(cgImage.width) * scale))
        let h = max(1, Int(CGFloat(cgImage.height) * scale))

        var pixelData = [UInt8](repeating: 0, count: w * h)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let ctx = CGContext(
                data: &pixelData,
                width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return 100 }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Laplacian kernel: [0,1,0, 1,-4,1, 0,1,0]
        let kernel: [Float] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        let floatPixels = pixelData.map { Float($0) / 255.0 }
        var output = [Float](repeating: 0, count: w * h)

        // Use vDSP convolution via Accelerate
        kernel.withUnsafeBufferPointer { kernelPtr in
            floatPixels.withUnsafeBufferPointer { srcPtr in
                output.withUnsafeMutableBufferPointer { dstPtr in
                    // vDSP_f3x3 applies a 3x3 filter
                    vDSP_f3x3(
                        srcPtr.baseAddress!, vDSP_Length(h), vDSP_Length(w),
                        kernelPtr.baseAddress!,
                        dstPtr.baseAddress!
                    )
                }
            }
        }

        // Variance of Laplacian response
        var mean: Float = 0
        var stddev: Float = 0
        vDSP_normalize(output, 1, nil, 1, &mean, &stddev, vDSP_Length(output.count))
        return stddev * stddev * 10000  // scale to a readable range
    }

    // MARK: - Average luminance via CIAreaAverage
    private func averageLuminance(image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 0.5 }
        let ci = CIImage(cgImage: cgImage)
        let extent = ci.extent

        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci,
                                                 kCIInputExtentKey: CIVector(cgRect: extent)]),
              let output = filter.outputImage
        else { return 0.5 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(output,
                         toBitmap: &bitmap,
                         rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        // Convert to luminance: Y = 0.299R + 0.587G + 0.114B
        let r = Float(bitmap[0]) / 255.0
        let g = Float(bitmap[1]) / 255.0
        let b = Float(bitmap[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    // MARK: - Overexposure ratio: fraction of pixels with luminance > 0.95
    private func overexposureRatio(image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 0 }

        // Sample at reduced resolution
        let scale = min(1.0, 100.0 / max(CGFloat(cgImage.width), CGFloat(cgImage.height)))
        let w = max(1, Int(CGFloat(cgImage.width) * scale))
        let h = max(1, Int(CGFloat(cgImage.height) * scale))
        let total = w * h

        var pixelData = [UInt8](repeating: 0, count: total * 4)
        guard let colorSpace = CGColorSpaceCreateDeviceRGB() as CGColorSpace?,
              let ctx = CGContext(
                data: &pixelData,
                width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return 0 }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var overexposed = 0
        let threshold: UInt8 = 242  // ~0.95 * 255
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            if pixelData[i] > threshold && pixelData[i+1] > threshold && pixelData[i+2] > threshold {
                overexposed += 1
            }
        }
        return Float(overexposed) / Float(total)
    }

    // MARK: - Contrast score (simplified from brightness and overexposure)
    private func contrastScore(brightness: Float, overexposure: Float) -> Float {
        // Low contrast if near-black or near-white
        let fromBlack = brightness
        let fromWhite = 1.0 - brightness - overexposure
        return min(1, max(0, min(fromBlack, fromWhite) * 4))
    }
}

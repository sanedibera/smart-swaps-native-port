import Foundation
import UIKit
import Vision

/// Lifted near-verbatim from `modules/native-ocr/ios/NativeOcrModule.swift`, per the brief's
/// own instruction ("already native, reuse it") - only the `ExpoModulesCore` wrapper
/// (`Module`/`AsyncFunction`/`Promise`) is stripped, replaced with a plain `async throws`
/// API. Kept in the app target, not `SmartSwapsKit` - the package also targets macOS (so
/// `swift test` can run without a simulator) and `UIKit` isn't available there.
enum NativeOcr {
    struct OcrLine { var text: String }
    struct OcrBlock { var text: String; var lines: [OcrLine] }
    struct OcrResult { var text: String; var blocks: [OcrBlock] }

    enum OcrError: Error { case imageLoadFailed(String), recognitionFailed(String) }

    static func recognize(uri: String) async throws -> OcrResult {
        guard let image = loadImage(from: uri), let cgImage = image.cgImage else {
            throw OcrError.imageLoadFailed("Could not load image at \(uri)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OcrError.recognitionFailed(error.localizedDescription))
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []

                // Vision returns observations in no guaranteed order. Receipts are read
                // top-to-bottom, so sort by vertical position (Vision's origin is
                // bottom-left, y increases upward -> larger y == higher on the page),
                // then left-to-right for lines on the same row.
                let sorted = observations.sorted { a, b in
                    let ay = a.boundingBox.midY
                    let by = b.boundingBox.midY
                    if abs(ay - by) > 0.01 { return ay > by }
                    return a.boundingBox.minX < b.boundingBox.minX
                }

                let lines: [OcrLine] = sorted.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    return OcrLine(text: candidate.string)
                }

                let fullText = lines.map(\.text).joined(separator: "\n")
                // Group all lines into a single block (matches the consumer's flatMap over blocks).
                let block = OcrBlock(text: fullText, lines: lines)
                continuation.resume(returning: OcrResult(text: fullText, blocks: [block]))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(image.imageOrientation), options: [:])

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OcrError.recognitionFailed(error.localizedDescription))
                }
            }
        }
    }

    private static func loadImage(from uri: String) -> UIImage? {
        if let url = URL(string: uri), url.isFileURL, let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        if let image = UIImage(contentsOfFile: uri) {
            return image
        }
        if let url = URL(string: uri), let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }

    private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

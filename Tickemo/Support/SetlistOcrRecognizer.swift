import Vision
import UIKit

/// Native on-device equivalent of RN's `@react-native-ml-kit/text-recognition`
/// call (`TextRecognition.recognize(imageUri, TextRecognitionScript.JAPANESE)`)
/// — Vision needs no third-party dependency and no network access. Like RN,
/// only the flattened, line-joined text is used (no per-block/box geometry
/// beyond a simple top-to-bottom sort to approximate reading order, since
/// RN doesn't do anything more sophisticated with ML Kit's output either).
enum SetlistOcrRecognizer {
  enum RecognitionError: Error {
    case invalidImage
  }

  static func recognizeText(in imageData: Data) async throws -> String {
    guard let uiImage = UIImage(data: imageData),
          let cgImage = uiImage.cgImage else {
      throw RecognitionError.invalidImage
    }

    // UIImage stores EXIF orientation separately from the pixel data.
    // cgImage loses that metadata, so Vision would process the raw pixel
    // layout (often landscape for portrait photos) and return bounding boxes
    // in the wrong coordinate space — making Y-based sorting produce garbage
    // order. Pass the orientation explicitly so Vision corrects for it.
    let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)

    return try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        // Vision's coordinate origin is bottom-left (Y increases upward).
        // Sort top-to-bottom (descending Y), then left-to-right (ascending X)
        // for observations at the same vertical position (e.g. index + title).
        let lines = observations
          .sorted {
            let yDiff = abs($0.boundingBox.midY - $1.boundingBox.midY)
            if yDiff > 0.015 { return $0.boundingBox.midY > $1.boundingBox.midY }
            return $0.boundingBox.minX < $1.boundingBox.minX
          }
          .compactMap { $0.topCandidates(1).first?.string }
        continuation.resume(returning: lines.joined(separator: "\n"))
      }
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["ja-JP", "en-US"]
      request.usesLanguageCorrection = true

      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}

// MARK: - UIImage.Orientation → CGImagePropertyOrientation

private extension CGImagePropertyOrientation {
  init(_ o: UIImage.Orientation) {
    switch o {
    case .up:            self = .up
    case .down:          self = .down
    case .left:          self = .left
    case .right:         self = .right
    case .upMirrored:    self = .upMirrored
    case .downMirrored:  self = .downMirrored
    case .leftMirrored:  self = .leftMirrored
    case .rightMirrored: self = .rightMirrored
    @unknown default:    self = .up
    }
  }
}

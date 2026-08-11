import UIKit

enum ImageCropping {
  /// Center-crops to a square and downscales, so cover photos stored in
  /// Core Data's Binary Data (and mirrored to CloudKit as CKAssets) aren't
  /// full-resolution originals for what's only ever shown as a thumbnail.
  static func squareCroppedJPEGData(from data: Data, maxDimension: CGFloat = 1200, quality: CGFloat = 0.85) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    let side = min(image.size.width, image.size.height)
    let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)
    let cropRectInPixels = CGRect(
      x: origin.x * image.scale,
      y: origin.y * image.scale,
      width: side * image.scale,
      height: side * image.scale
    )
    guard let cgImage = image.cgImage?.cropping(to: cropRectInPixels) else { return nil }

    var square = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    if square.size.width > maxDimension {
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: maxDimension, height: maxDimension))
      square = renderer.image { _ in
        square.draw(in: CGRect(x: 0, y: 0, width: maxDimension, height: maxDimension))
      }
    }
    return square.jpegData(compressionQuality: quality)
  }

  /// Downscales without cropping, preserving the original aspect ratio —
  /// for game photos (`allowsEditing: false` on the RN side, unlike the
  /// square-cropped cover/player photo), so a snapshot's framing isn't
  /// altered, only its resolution when it's larger than needed for a
  /// thumbnail grid.
  static func downsizedJPEGData(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.85) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    let longestSide = max(image.size.width, image.size.height)
    guard longestSide > maxDimension else { return image.jpegData(compressionQuality: quality) }

    let scale = maxDimension / longestSide
    let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let resized = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return resized.jpegData(compressionQuality: quality)
  }
}

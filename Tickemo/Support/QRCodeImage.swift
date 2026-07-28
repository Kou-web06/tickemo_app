import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCodeImage {
  static func image(for string: String, scale: CGFloat = 8) -> UIImage? {
    guard !string.isEmpty else { return nil }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext()
    guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }
}

struct QRCodeView: View {
  let value: String

  var body: some View {
    Group {
      if !value.isEmpty, let uiImage = QRCodeImage.image(for: value) {
        Image(uiImage: uiImage)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "qrcode")
          .resizable()
          .scaledToFit()
          .padding(6)
          .foregroundStyle(.tertiary)
      }
    }
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  init(value: String?) {
    self.value = value ?? ""
  }
}

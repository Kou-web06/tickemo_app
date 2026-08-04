import SwiftUI
import UIKit

/// Wraps `UIImagePickerController` with `allowsEditing = true`, which gives
/// an interactive, user-positioned square-crop UI — unlike
/// `PHPickerViewController`/SwiftUI's `PhotosPicker`, which has no
/// built-in crop step. This is the native equivalent of RN's
/// `expo-image-picker { allowsEditing: true, aspect: [1,1] }` used by
/// ProfileEditScreen. A screen-local exception to this codebase's usual
/// `PhotosPicker` + automatic center-crop convention (see
/// `RecordFormView`/`ImageCropping.swift`), specifically because
/// ProfileEditView is in scope for RN-exact interactive-crop parity.
struct ImagePickerRepresentable: UIViewControllerRepresentable {
  var sourceType: UIImagePickerController.SourceType = .photoLibrary
  var allowsEditing: Bool = true
  var onPick: (Data) -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = sourceType
    picker.allowsEditing = allowsEditing
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onPick: onPick)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onPick: (Data) -> Void

    init(onPick: @escaping (Data) -> Void) {
      self.onPick = onPick
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      picker.dismiss(animated: true)
      let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
      guard let data = image?.jpegData(compressionQuality: 0.9) else { return }
      // Delay lets SwiftUI finish processing the sheet dismissal before the
      // caller presents another sheet or updates state — without this, setting
      // new sheet state while the picker is still animating out causes a crash.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
        onPick(data)
      }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      picker.dismiss(animated: true)
    }
  }
}

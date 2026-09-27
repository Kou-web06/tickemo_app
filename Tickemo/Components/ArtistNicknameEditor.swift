import SwiftUI

/// アーティストのあだ名（表示名）を編集するアラート。アーティスト詳細の
/// ヘッダーと、記録フォームのアーティスト欄（選択済みチップ）の両方から
/// 開けるように共通化している。
private struct ArtistNicknameEditorModifier: ViewModifier {
  @Binding var isPresented: Bool
  let artistName: String

  @State private var draft = ""

  func body(content: Content) -> some View {
    content
      .onChange(of: isPresented) { _, presented in
        guard presented else { return }
        draft = ArtistNicknameStore.shared.nickname(for: artistName) ?? ""
      }
      .alert("表示名を編集", isPresented: $isPresented) {
        TextField(artistName, text: $draft)
        Button("キャンセル", role: .cancel) {}
        Button("保存") {
          ArtistNicknameStore.shared.setNickname(draft, for: artistName)
          // ウィジェットは App Group に書き出した名前を出しているので書き直す
          WidgetReloaderService.syncFromStore()
        }
      } message: {
        Text("アプリ内の表示だけが変わります。Reportの集計やApple Musicの検索には「\(artistName)」が使われます。空欄で元に戻ります。")
      }
  }
}

extension View {
  func artistNicknameEditor(isPresented: Binding<Bool>, artistName: String) -> some View {
    modifier(ArtistNicknameEditorModifier(isPresented: isPresented, artistName: artistName))
  }
}

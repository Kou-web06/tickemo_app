import SwiftUI

/// Ports LiveEditScreen.tsx's `TimePickerModal`: a row showing the current
/// "HH:mm" value that opens a sheet with a two-column wheel (Hour 0-23,
/// Minute restricted to :00/:30 — RN never allows any other minute value)
/// plus Cancel/Done buttons. `RecordFormView` binds this directly to a
/// "HH:mm" string, matching how the value is actually stored on
/// `CD_ChekiRecord.startTime`/`endTime`.
struct TimeWheelPickerField: View {
  var label: String
  @Binding var value: String

  @State private var isPresented = false
  @State private var draftHour = 18
  @State private var draftMinute = 0

  private static let minuteOptions = [0, 30]

  var body: some View {
    Button {
      let parsed = Self.parse(value)
      draftHour = parsed.hour
      draftMinute = parsed.minute
      isPresented = true
    } label: {
      HStack {
        Text(label).foregroundStyle(.primary)
        Spacer()
        Text(value).foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $isPresented) {
      NavigationStack {
        // 以前は SwiftUI の Picker(.wheel) を2つ横に並べていたが、実機で
        // ホイール操作中に落ちるという報告があった。SwiftUI 内部の
        // CoreCoordinator が選択行を自前の配列で引く箇所は範囲外アクセスで
        // 落ちうる（シミュレータで確認）ので、UIKit の UIPickerView 1つに
        // 時・分の2列を持たせ、行番号は必ず範囲チェックしてから使う。
        HourMinuteWheel(hour: $draftHour, minute: $draftMinute, minuteOptions: Self.minuteOptions)
        .navigationTitle(label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button { isPresented = false } label: {
              HugeIconView(icon: HugeIcons.cancel01, size: 17)
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button {
              value = String(format: "%02d:%02d", draftHour, draftMinute)
              isPresented = false
            } label: {
              Image(systemName: "checkmark")
                .fontWeight(.semibold)
            }
          }
        }
      }
      .presentationDetents([.height(280)])
    }
  }

  private static func parse(_ value: String) -> (hour: Int, minute: Int) {
    let parts = value.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2, (0..<24).contains(parts[0]) else { return (18, 0) }
    return (parts[0], parts[1] == 30 ? 30 : 0)
  }
}

/// 時（0〜23）と分（minuteOptions）の2列ホイール。
private struct HourMinuteWheel: UIViewRepresentable {
  @Binding var hour: Int
  @Binding var minute: Int
  let minuteOptions: [Int]

  private static let hours = Array(0..<24)

  func makeCoordinator() -> Coordinator {
    Coordinator(hour: $hour, minute: $minute, minuteOptions: minuteOptions)
  }

  func makeUIView(context: Context) -> UIPickerView {
    let picker = UIPickerView()
    picker.dataSource = context.coordinator
    picker.delegate = context.coordinator
    select(in: picker, animated: false)
    return picker
  }

  func updateUIView(_ picker: UIPickerView, context: Context) {
    context.coordinator.hour = $hour
    context.coordinator.minute = $minute
    select(in: picker, animated: false)
  }

  /// バインディングの値に合わせてホイールを合わせる。すでに合っていれば
  /// 触らない（スクロール中に選択し直して操作を邪魔しないため）
  private func select(in picker: UIPickerView, animated: Bool) {
    if let row = Self.hours.firstIndex(of: hour), picker.selectedRow(inComponent: 0) != row {
      picker.selectRow(row, inComponent: 0, animated: animated)
    }
    if let row = minuteOptions.firstIndex(of: minute), picker.selectedRow(inComponent: 1) != row {
      picker.selectRow(row, inComponent: 1, animated: animated)
    }
  }

  final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    var hour: Binding<Int>
    var minute: Binding<Int>
    let minuteOptions: [Int]

    init(hour: Binding<Int>, minute: Binding<Int>, minuteOptions: [Int]) {
      self.hour = hour
      self.minute = minute
      self.minuteOptions = minuteOptions
    }

    private func values(for component: Int) -> [Int] {
      component == 0 ? HourMinuteWheel.hours : minuteOptions
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
      values(for: component).count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
      let options = values(for: component)
      guard options.indices.contains(row) else { return nil }
      return String(format: "%02d", options[row])
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
      let options = values(for: component)
      guard options.indices.contains(row) else { return }
      if component == 0 {
        hour.wrappedValue = options[row]
      } else {
        minute.wrappedValue = options[row]
      }
    }
  }
}

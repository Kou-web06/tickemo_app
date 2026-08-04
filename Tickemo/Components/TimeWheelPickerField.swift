import SwiftUI

/// Ports LiveEditScreen.tsx's `TimePickerModal`: a row showing the current
/// "HH:mm" value that opens a sheet with two wheel pickers (Hour 0-23,
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
        HStack(spacing: 0) {
          Picker("Hour", selection: $draftHour) {
            ForEach(0..<24, id: \.self) { hour in
              Text(String(format: "%02d", hour)).tag(hour)
            }
          }
          .pickerStyle(.wheel)

          Picker("Minute", selection: $draftMinute) {
            ForEach(Self.minuteOptions, id: \.self) { minute in
              Text(String(format: "%02d", minute)).tag(minute)
            }
          }
          .pickerStyle(.wheel)
        }
        .labelsHidden()
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

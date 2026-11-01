import SwiftUI

/// 分辨率选择: 预设列表加自定义宽高.
struct ResolutionPicker: View {
    @Binding var presetID: String
    @Binding var customWidth: String
    @Binding var customHeight: String

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $presetID) {
                ForEach(DisplayModeCatalog.resolutionPresets) { preset in
                    Text(preset.label).tag(preset.id)
                }
                Text("自定义").tag("custom")
            }
            .labelsHidden()
            .frame(width: 170)

            if presetID == "custom" {
                TextField("宽", text: $customWidth)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                Text("x")
                    .foregroundStyle(Theme.secondaryText)
                TextField("高", text: $customHeight)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// 刷新率选择.
struct RefreshRatePicker: View {
    @Binding var refreshRate: Double

    var body: some View {
        Picker("", selection: $refreshRate) {
            ForEach(DisplayModeCatalog.refreshRates, id: \.self) { rate in
                Text(label(for: rate)).tag(rate)
            }
        }
        .labelsHidden()
        .frame(width: 130)
    }

    private func label(for rate: Double) -> String {
        rate.rounded() == rate ? "\(Int(rate)) Hz" : String(format: "%.2f Hz", rate)
    }
}

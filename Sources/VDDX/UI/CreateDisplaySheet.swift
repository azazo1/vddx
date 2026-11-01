import SwiftUI

struct CreateDisplaySheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var presetID = "1920x1080"
    @State private var customWidth = "1920"
    @State private var customHeight = "1080"
    @State private var refreshRate: Double = 60
    @State private var hiDPI = true
    @State private var autoRestore = true
    @State private var errorMessage: String?

    init(model: AppModel) {
        self.model = model
        _name = State(initialValue: model.suggestedDisplayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("新建虚拟屏")
                .font(.system(size: 15, weight: .semibold))
                .padding(.bottom, 16)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("名称").gridColumnAlignment(.trailing).foregroundStyle(Theme.secondaryText)
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                GridRow {
                    Text("分辨率").gridColumnAlignment(.trailing).foregroundStyle(Theme.secondaryText)
                    ResolutionPicker(presetID: $presetID, customWidth: $customWidth, customHeight: $customHeight)
                }
                GridRow {
                    Text("刷新率").gridColumnAlignment(.trailing).foregroundStyle(Theme.secondaryText)
                    RefreshRatePicker(refreshRate: $refreshRate)
                }
                GridRow {
                    Text("").gridColumnAlignment(.trailing)
                    Toggle("HiDPI (像素加倍)", isOn: $hiDPI)
                }
                GridRow {
                    Text("").gridColumnAlignment(.trailing)
                    Toggle("应用启动时自动重建", isOn: $autoRestore)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("创建") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(width: 460)
    }

    private func resolvedSize() -> (Int, Int)? {
        if presetID == "custom" {
            guard let width = Int(customWidth), let height = Int(customHeight) else { return nil }
            return (width, height)
        }
        guard let preset = DisplayModeCatalog.resolutionPresets.first(where: { $0.id == presetID }) else {
            return nil
        }
        return (preset.width, preset.height)
    }

    private func create() {
        guard let (width, height) = resolvedSize() else {
            errorMessage = "请输入有效的分辨率"
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "名称不能为空"
            return
        }
        if model.displayManager.displays.contains(where: { $0.profile.name == trimmedName }) {
            errorMessage = "已存在同名虚拟屏"
            return
        }
        let profile = DisplayProfile(
            name: trimmedName,
            logicalWidth: width,
            logicalHeight: height,
            refreshRate: refreshRate,
            hiDPI: hiDPI,
            autoRestore: autoRestore
        )
        guard profile.isValid else {
            errorMessage = "分辨率需在 640x480 到 7680x4320 之间"
            return
        }
        do {
            try model.displayManager.create(profile)
            Log.shared.info("用户创建虚拟屏: \(trimmedName) \(width)x\(height)@\(refreshRate) hiDPI=\(hiDPI)")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

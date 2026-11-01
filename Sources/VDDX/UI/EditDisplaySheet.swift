import SwiftUI

struct EditDisplaySheet: View {
    @ObservedObject var model: AppModel
    let display: VirtualDisplay
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var presetID: String
    @State private var customWidth: String
    @State private var customHeight: String
    @State private var refreshRate: Double
    @State private var hiDPI: Bool
    @State private var autoRestore: Bool
    @State private var errorMessage: String?

    init(model: AppModel, display: VirtualDisplay) {
        self.model = model
        self.display = display
        let profile = display.profile
        _name = State(initialValue: profile.name)
        _customWidth = State(initialValue: "\(profile.logicalWidth)")
        _customHeight = State(initialValue: "\(profile.logicalHeight)")
        if let preset = DisplayModeCatalog.resolutionPresets.first(where: {
            $0.width == profile.logicalWidth && $0.height == profile.logicalHeight
        }) {
            _presetID = State(initialValue: preset.id)
        } else {
            _presetID = State(initialValue: "custom")
        }
        _refreshRate = State(initialValue: profile.refreshRate)
        _hiDPI = State(initialValue: profile.hiDPI)
        _autoRestore = State(initialValue: profile.autoRestore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("编辑虚拟屏")
                .font(.system(size: 15, weight: .semibold))
                .padding(.bottom, 4)
            Text("Display ID \(display.displayID)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.tertiaryText)
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

            if requiresRebuild {
                Text("分辨率, 刷新率或 HiDPI 的修改会重建这块虚拟屏.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 12)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(requiresRebuild ? "保存并重建" : "保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(width: 460)
    }

    private var requiresRebuild: Bool {
        guard let (width, height) = resolvedSize() else { return false }
        let profile = display.profile
        return width != profile.logicalWidth
            || height != profile.logicalHeight
            || refreshRate != profile.refreshRate
            || hiDPI != profile.hiDPI
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

    private func save() {
        guard let (width, height) = resolvedSize() else {
            errorMessage = "请输入有效的分辨率"
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "名称不能为空"
            return
        }
        if model.displayManager.displays.contains(where: { $0.id != display.id && $0.profile.name == trimmedName }) {
            errorMessage = "已存在同名虚拟屏"
            return
        }
        let profile = DisplayProfile(
            id: display.profile.id,
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
            if requiresRebuild {
                try model.displayManager.rebuild(display, with: profile)
            } else {
                model.displayManager.update(display, with: profile)
            }
            Log.shared.info("用户更新虚拟屏配置: \(trimmedName)")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

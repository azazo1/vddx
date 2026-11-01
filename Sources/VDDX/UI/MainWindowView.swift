import AppKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var manager: VirtualDisplayManager

    let onMirror: (VirtualDisplay) -> Void
    let onOpenSettings: () -> Void
    let onCheckUpdates: () -> Void
    let onOpenUpdateWindow: () -> Void

    @State private var isCreating = false
    @State private var editingDisplay: VirtualDisplay?
    @State private var deletingDisplay: VirtualDisplay?

    init(
        model: AppModel,
        onMirror: @escaping (VirtualDisplay) -> Void,
        onOpenSettings: @escaping () -> Void,
        onCheckUpdates: @escaping () -> Void,
        onOpenUpdateWindow: @escaping () -> Void
    ) {
        self.model = model
        self._manager = ObservedObject(wrappedValue: model.displayManager)
        self.onMirror = onMirror
        self.onOpenSettings = onOpenSettings
        self.onCheckUpdates = onCheckUpdates
        self.onOpenUpdateWindow = onOpenUpdateWindow
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            content
            Divider().opacity(0.45)
            statusBar
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isCreating) {
            CreateDisplaySheet(model: model)
        }
        .sheet(item: $editingDisplay) { display in
            EditDisplaySheet(model: model, display: display)
        }
        .alert("销毁虚拟屏?", isPresented: deleteAlertBinding) {
            Button("销毁", role: .destructive) {
                if let display = deletingDisplay {
                    manager.forget(display)
                    Log.shared.info("用户销毁虚拟屏: \(display.profile.name)")
                }
                deletingDisplay = nil
            }
            Button("取消", role: .cancel) {
                deletingDisplay = nil
            }
        } message: {
            Text("该屏会立即从系统中移除, 并取消它的启动时自动重建配置. 正在镜像它的窗口会断开.")
        }
        .onReceive(model.$createDisplayRequest) { requested in
            guard requested else { return }
            isCreating = true
            model.createDisplayRequest = false
        }
    }

    // MARK: - 区块

    private var header: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 74)
            Text("VDDX")
                .font(.system(size: 13, weight: .semibold))
            Text(AppInfo.displayVersion)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button {
                isCreating = true
            } label: {
                Label("新建虚拟屏", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("n", modifiers: .command)

            IconButton(systemName: "rectangle.on.rectangle", help: "打开系统显示器设置") {
                SystemSettingsLink.displays.open()
            }

            IconButton(systemName: "gearshape", help: "设置", action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if manager.displays.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(manager.displays) { display in
                        DisplayCardView(
                            display: display,
                            isAlive: display.isAlive,
                            onMirror: { onMirror(display) },
                            onEdit: { editingDisplay = display },
                            onDelete: { deletingDisplay = display }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .id(manager.screenChangeTick)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "display")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text("还没有虚拟屏")
                .font(.system(size: 14, weight: .medium))
            Text("创建一块虚拟屏后, 可以在系统设置的显示器排列里使用它.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("新建虚拟屏") {
                isCreating = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let available = model.updates.availableVersion {
                Button("新版本 \(available) 可用") {
                    onOpenUpdateWindow()
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
            } else {
                Text("VDDX \(AppInfo.displayVersion)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
            }

            if let warning = model.settingsWarning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            Spacer()

            if let error = manager.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Text("\(manager.displays.count) 块虚拟屏")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)

            Button("打开数据目录") {
                NSWorkspace.shared.open(AppPaths.dataDirectory)
            }
            .buttonStyle(.link)
            .font(.system(size: 10.5))
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deletingDisplay != nil },
            set: { if !$0 { deletingDisplay = nil } }
        )
    }
}

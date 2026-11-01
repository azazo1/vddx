import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let onCheckUpdates: () -> Void

    var body: some View {
        Form {
            Section("启动与窗口") {
                Toggle("启动时隐藏主窗口, 仅驻留菜单栏", isOn: binding(\.general.hideMainWindowOnLaunch))
                Toggle("主窗口隐藏时同时隐藏 Dock 图标", isOn: binding(\.general.hideDockWhenWindowHidden))
            }

            Section("日志") {
                Picker("日志级别", selection: binding(\.general.logLevel)) {
                    ForEach(["error", "warn", "info", "debug", "trace"], id: \.self) { level in
                        Text(level).tag(level)
                    }
                }
                HStack {
                    Text(AppPaths.logDirectory.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("打开") {
                        NSWorkspace.shared.open(AppPaths.logDirectory)
                    }
                }
            }

            Section("更新") {
                Toggle("自动检查更新", isOn: binding(\.updates.automaticallyChecks))
                HStack {
                    Text("当前版本 \(AppInfo.displayVersion)")
                    Spacer()
                    Button("检查更新") {
                        onCheckUpdates()
                    }
                }
            }

            Section("屏幕录制权限") {
                HStack {
                    Text(ScreenCapturePermission.isGranted ? "已授权" : "未授权")
                        .foregroundStyle(ScreenCapturePermission.isGranted ? Color.green : Color.orange)
                    Spacer()
                    Button("打开系统设置") {
                        SystemSettingsLink.screenRecording.open()
                    }
                }
                Text("镜像窗口需要该权限. macOS 15 起系统不再自动弹窗, 需要手动添加 VDDX 并勾选.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("关于") {
                HStack {
                    Text("数据目录")
                    Spacer()
                    Button(AppPaths.dataDirectory.path) {
                        NSWorkspace.shared.open(AppPaths.dataDirectory)
                    }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                HStack {
                    Text("源代码")
                    Spacer()
                    Link(AppInfo.repositoryURL.absoluteString, destination: AppInfo.repositoryURL)
                        .lineLimit(1)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 460)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                model.updateSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

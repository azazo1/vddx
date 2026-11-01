import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("VDDX")
                .font(.system(size: 18, weight: .semibold))
            Text(AppInfo.displayVersion)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
            Text("macOS 虚拟屏管理工具")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
            Link("github.com/\(AppInfo.repositorySlug)", destination: AppInfo.repositoryURL)
                .font(.system(size: 11))
            Divider()
                .padding(.vertical, 4)
            Text("MIT License · © 2026 azazo1")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(26)
        .frame(width: 320, height: 280)
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 VDDX"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: AboutView())
    }

    required init?(coder: NSCoder) {
        nil
    }
}

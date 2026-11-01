import AppKit
import SwiftUI

/// 通用视觉样式.
enum Theme {
    static let cardCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 8

    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color(nsColor: .separatorColor).opacity(0.55)
    static let cardHoverStroke = Color.accentColor.opacity(0.55)

    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
}

/// 带留白点击区域的图标按钮.
struct IconButton: View {
    let systemName: String
    var help: String = ""
    var tint: Color? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint ?? Color.primary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlCornerRadius)
                        .fill(isHovering ? Color.primary.opacity(0.07) : Color.clear)
                )
        }
        .buttonStyle(IconPressStyle())
        .onHover { isHovering = $0 }
        .help(help)
    }
}

private struct IconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.controlCornerRadius)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.14) : Color.clear)
            )
    }
}

/// 虚拟屏存活状态徽章.
struct StatusBadge: View {
    let isAlive: Bool

    var body: some View {
        let color = isAlive ? Color.green : Color.orange
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5.5, height: 5.5)
            Text(isAlive ? "运行中" : "已断开")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

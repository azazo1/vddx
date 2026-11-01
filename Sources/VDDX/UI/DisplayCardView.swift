import SwiftUI

struct DisplayCardView: View {
    let display: VirtualDisplay
    let isAlive: Bool
    let onMirror: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "display")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(display.profile.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    StatusBadge(isAlive: isAlive)
                }
                Text(display.profile.detailLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text("Display ID \(display.displayID)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                Button("镜像", action: onMirror)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isAlive)
                    .help("在窗口中显示这块虚拟屏的画面")
                IconButton(systemName: "slider.horizontal.3", help: "编辑配置", action: onEdit)
                IconButton(systemName: "trash", help: "销毁虚拟屏", tint: .red, action: onDelete)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(isHovering ? Theme.cardHoverStroke : Theme.cardStroke, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

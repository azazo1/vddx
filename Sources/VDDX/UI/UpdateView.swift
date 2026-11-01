import SwiftUI

struct UpdateView: View {
    @ObservedObject var model: AppModel
    let release: UpdateRelease
    let onDownload: (UpdateRelease) -> Void
    let onInstall: (UpdateRelease, URL) -> Void
    let onSkip: (UpdateRelease) -> Void
    let onOpenReleasePage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("新版本 \(release.tagName)")
                        .font(.system(size: 15, weight: .semibold))
                    Text("当前版本 \(AppInfo.displayVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }

            ScrollView {
                Text(release.notes.isEmpty ? "此版本没有提供更新说明." : release.notes)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 210)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )

            statusRow

            HStack(spacing: 10) {
                Button("打开发布页面", action: onOpenReleasePage)
                Spacer()
                Button("跳过此版本") {
                    onSkip(release)
                }
                trailingActions
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.updates.state {
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在下载并校验更新包...")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        case .ready(_, let url):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("已下载并通过校验: \(url.lastPathComponent)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(2)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingActions: some View {
        switch model.updates.state {
        case .ready(_, let url):
            Button("重启并更新") {
                onInstall(release, url)
            }
            .buttonStyle(.borderedProminent)
        case .downloading:
            EmptyView()
        default:
            Button("下载更新") {
                onDownload(release)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

import Foundation

/// 需要自动恢复的虚拟屏配置列表.
@MainActor
final class DisplayProfileStore {
    private struct FileContent: Codable {
        var version: Int = 1
        var profiles: [DisplayProfile] = []
    }

    private let url: URL
    private(set) var profiles: [DisplayProfile] = []

    init(url: URL = AppPaths.dataDirectory.appendingPathComponent("displays.json")) {
        self.url = url
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let content = try JSONDecoder().decode(FileContent.self, from: data)
            profiles = content.profiles
            Log.shared.info("已加载 \(profiles.count) 个虚拟屏配置")
        } catch {
            Log.shared.error("虚拟屏配置加载失败: \(error.localizedDescription)")
            profiles = []
        }
    }

    private func save() {
        do {
            let content = FileContent(profiles: profiles)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(content)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.shared.error("虚拟屏配置保存失败: \(error.localizedDescription)")
        }
    }

    func set(_ profile: DisplayProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func remove(id: UUID) {
        let before = profiles.count
        profiles.removeAll { $0.id == id }
        if profiles.count != before {
            save()
        }
    }

    func contains(id: UUID) -> Bool {
        profiles.contains { $0.id == id }
    }
}

import Foundation

/// 本地歌词存储管理器，用于保存和读取用户编辑的歌词
class LyricStorage {
    static let shared = LyricStorage()

    private let fileManager = FileManager.default
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lyricDir = appSupport.appendingPathComponent("LyricMist/EditedLyrics")

        // 确保目录存在
        if !fileManager.fileExists(atPath: lyricDir.path) {
            try? fileManager.createDirectory(at: lyricDir, withIntermediateDirectories: true)
        }

        return lyricDir
    }

    private init() {}

    /// 生成歌词的唯一文件名
    private func fileName(for title: String, artist: String) -> String {
        let key = "\(artist)-\(title)"
        return key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "unknown"
    }

    /// 保存编辑后的歌词
    func saveLyrics(_ lyrics: [LyricLine], title: String, artist: String) {
        let fileName = fileName(for: title, artist: artist) + ".json"
        let fileURL = storageDirectory.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(lyrics)
            try data.write(to: fileURL)
            print("✅ 歌词已保存到: \(fileURL.path)")
        } catch {
            print("❌ 保存歌词失败: \(error)")
        }
    }

    /// 读取编辑后的歌词
    func loadLyrics(title: String, artist: String) -> [LyricLine]? {
        let fileName = fileName(for: title, artist: artist) + ".json"
        let fileURL = storageDirectory.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let lyrics = try JSONDecoder().decode([LyricLine].self, from: data)
            print("✅ 已加载编辑的歌词: \(title) - \(artist)")
            return lyrics
        } catch {
            print("❌ 读取歌词失败: \(error)")
            return nil
        }
    }

    /// 删除编辑后的歌词（恢复使用在线歌词）
    func deleteLyrics(title: String, artist: String) {
        let fileName = fileName(for: title, artist: artist) + ".json"
        let fileURL = storageDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
            print("✅ 已删除编辑的歌词: \(title) - \(artist)")
        }
    }

    /// 检查是否存在编辑后的歌词
    func hasEditedLyrics(title: String, artist: String) -> Bool {
        let fileName = fileName(for: title, artist: artist) + ".json"
        let fileURL = storageDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path)
    }
}

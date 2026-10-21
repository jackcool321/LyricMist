import Foundation

struct LyricLine: Codable, Equatable {
    let time: Double
    let text: String
}

class LyricFetcher {
    private let cache = NSCache<NSString, CachedLyrics>()

    func fetchLyrics(title: String, artist: String) async -> [LyricLine] {
        let cacheKey = "\(artist)-\(title)" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached.lyrics
        }

        var lyrics: [LyricLine] = []

        lyrics = await fetchFromLrclib(title: title, artist: artist)

        if lyrics.isEmpty {
            lyrics = await fetchFromNetease(title: title, artist: artist)
        }

        if !lyrics.isEmpty {
            let cached = CachedLyrics(lyrics: lyrics)
            cache.setObject(cached, forKey: cacheKey)
        }

        return lyrics
    }

    private func fetchFromLrclib(title: String, artist: String) async -> [LyricLine] {
        let query = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://lrclib.net/api/search?q=\(query)"

        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }

            guard let results = try? JSONDecoder().decode([LrclibResult].self, from: data),
                  let first = results.first,
                  let lrcContent = first.syncedLyrics else {
                return []
            }

            return parseLRC(lrcContent)
        } catch {
            print("Lrclib fetch error: \(error)")
            return []
        }
    }

    private func fetchFromNetease(title: String, artist: String) async -> [LyricLine] {
        guard let searchData = await searchNeteaseMusic(title: title, artist: artist),
              let songId = searchData.first else {
            return []
        }

        return await getNeteaseeLyrics(songId: songId)
    }

    private func searchNeteaseMusic(title: String, artist: String) async -> [Int]? {
        let keywords = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://music.163.com/api/search/get/web?s=\(keywords)&type=1&offset=0&limit=5"

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let songs = result["songs"] as? [[String: Any]] {
                return songs.compactMap { $0["id"] as? Int }
            }
        } catch {
            print("Netease search error: \(error)")
        }

        return nil
    }

    private func getNeteaseeLyrics(songId: Int) async -> [LyricLine] {
        let urlString = "https://music.163.com/api/song/lyric?id=\(songId)&lv=1&kv=1&tv=-1"

        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let lrc = json["lrc"] as? [String: Any],
               let lrcContent = lrc["lyric"] as? String {
                return parseLRC(lrcContent)
            }
        } catch {
            print("Netease lyrics error: \(error)")
        }

        return []
    }

    private func parseLRC(_ lrcContent: String) -> [LyricLine] {
        var lyrics: [LyricLine] = []

        let lines = lrcContent.components(separatedBy: .newlines)

        for line in lines {
            if let lyricLine = parseLRCLine(line) {
                lyrics.append(lyricLine)
            }
        }

        return lyrics.sorted { $0.time < $1.time }
    }

    private func parseLRCLine(_ line: String) -> LyricLine? {
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\](.+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        guard match.numberOfRanges == 5 else { return nil }

        let minutesRange = Range(match.range(at: 1), in: line)
        let secondsRange = Range(match.range(at: 2), in: line)
        let fractionalRange = Range(match.range(at: 3), in: line)
        let textRange = Range(match.range(at: 4), in: line)

        guard let minutesRange = minutesRange,
              let secondsRange = secondsRange,
              let fractionalRange = fractionalRange,
              let textRange = textRange else {
            return nil
        }

        let minutes = Double(line[minutesRange]) ?? 0
        let seconds = Double(line[secondsRange]) ?? 0
        // LRC 既可能使用两位小数（百分之一秒），也可能使用三位小数（千分之一秒）。
        // 统一除以 1000 会让两位小数的时间轴被压缩 10 倍，导致歌曲越往后越跑快。
        let fractionalPart = String(line[fractionalRange])
        let fraction = Double(fractionalPart) ?? 0
        let fractionalSeconds = fraction / (fractionalPart.count == 2 ? 100.0 : 1000.0)
        let text = String(line[textRange])

        let time = minutes * 60 + seconds + fractionalSeconds

        return LyricLine(time: time, text: text.trimmingCharacters(in: .whitespaces))
    }
}

class CachedLyrics {
    let lyrics: [LyricLine]

    init(lyrics: [LyricLine]) {
        self.lyrics = lyrics
    }
}

struct LrclibResult: Codable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

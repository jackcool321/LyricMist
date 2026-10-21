import Foundation
import Combine

enum MusicPlayer {
    case spotify
    case appleMusic
    case none
}

struct TrackInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let position: Double
    let isPlaying: Bool
    let player: MusicPlayer

    // 播放进度和暂停状态不属于歌曲身份。
    var lyricIdentity: String {
        "\(player)|\(title.count):\(title)|\(artist.count):\(artist)|\(album)"
    }
}

enum PlaybackRepeatMode: String {
    case off, all, one

    var title: String {
        switch self {
        case .off: return "循环关闭"
        case .all: return "列表循环"
        case .one: return "单曲循环"
        }
    }

    func next(for player: MusicPlayer) -> PlaybackRepeatMode {
        switch self {
        case .off: return .all
        case .all: return player == .appleMusic ? .one : .off
        case .one: return .off
        }
    }
}

struct PlaybackOptions: Equatable {
    let shuffle: Bool
    let repeatMode: PlaybackRepeatMode
    let canShuffle: Bool
    let canRepeat: Bool

    init?(response: String) {
        let parts = response.components(separatedBy: "|||")
        guard parts.count == 4,
              let shuffle = Self.boolean(parts[0]),
              let repeatMode = PlaybackRepeatMode(rawValue: parts[1]),
              let canShuffle = Self.boolean(parts[2]),
              let canRepeat = Self.boolean(parts[3]) else { return nil }
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.canShuffle = canShuffle
        self.canRepeat = canRepeat
    }

    private static func boolean(_ value: String) -> Bool? {
        switch value {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    // 显式转换为文本，避免 AppleScript 布尔值/枚举的隐式拼接。
    static func readCommand(for player: MusicPlayer) -> String {
        if player == .spotify {
            return """
            set repeatValue to "off"
            if repeating then set repeatValue to "all"
            return (shuffling as text) & "|||" & repeatValue & "|||" & (shuffling enabled as text) & "|||" & (repeating enabled as text)
            """
        }
        return """
        set repeatValue to "off"
        if song repeat is all then set repeatValue to "all"
        if song repeat is one then set repeatValue to "one"
        return (shuffle enabled as text) & "|||" & repeatValue & "|||true|||true"
        """
    }
}

class MusicPlayerManager: ObservableObject {
    @Published var currentTrack: TrackInfo?
    @Published var currentLyrics: [LyricLine] = []
    @Published var permissionError: String?
    @Published private(set) var playbackOptions: PlaybackOptions?
    @Published var playbackControlError: String?
    private var optionsPlayer: MusicPlayer = .none

    // 可注入脚本执行器，测试无需启动或改变用户的播放器。
    private let executePlaybackScript: (String) throws -> String
    private let pollingQueue = DispatchQueue(label: "LyricMist.playerPolling", qos: .userInitiated)
    private var pollInFlight = false
    private var monitoringGeneration = 0

    init(executePlaybackScript: @escaping (String) throws -> String = MusicPlayerManager.runPlaybackScript) {
        self.executePlaybackScript = executePlaybackScript
    }

    static func runPlaybackScript(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw NSError(domain: "LyricMist.Playback", code: -1)
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            throw NSError(domain: "LyricMist.Playback",
                          code: error["NSAppleScriptErrorNumber"] as? Int ?? -1)
        }
        return result.stringValue ?? ""
    }

    // 插值预测用的状态
    @Published var interpolatedPosition: Double = 0.0
    private var lastRealPosition: Double = 0.0
    private var lastUpdateTime: Date = Date()
    private var isCurrentlyPlaying: Bool = false
    private var updateCounter = 0

    private var timer: Timer?
    private let lyricFetcher = LyricFetcher()
    private var hasShownPermissionError = false

    func startMonitoring() {
        guard timer == nil else { return }
        // 首次启动时请求权限
        requestPermissions()

        // 提高更新频率到 0.05 秒（20fps），让歌词高亮更平滑
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateCurrentTrack()
        }

        // 使用 common run loop mode 以提高响应性
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func requestPermissions() {
        // 尝试执行一个简单的 AppleScript 来触发权限请求
        // 这会让系统弹出权限对话框
        DispatchQueue.global(qos: .userInitiated).async {
            let spotifyScript = """
            tell application "System Events"
                if exists (process "Spotify") then
                    tell application "Spotify" to get name
                end if
            end tell
            """
            if let appleScript = NSAppleScript(source: spotifyScript) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("Spotify 权限请求: \(error)")
                }
            }

            let musicScript = """
            tell application "System Events"
                if exists (process "Music") then
                    tell application "Music" to get name
                end if
            end tell
            """
            if let appleScript = NSAppleScript(source: musicScript) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("Music 权限请求: \(error)")
                }
            }
        }
    }

    func stopMonitoring() {
        monitoringGeneration += 1
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentTrack() {
        let now = Date()
        updateCounter += 1

        // 每 4 次更新（0.2 秒）从播放器读取一次真实位置（减少 AppleScript 调用开销）
        let shouldFetchRealPosition = updateCounter % 4 == 0

        if shouldFetchRealPosition && !pollInFlight {
            pollInFlight = true
            let generation = monitoringGeneration
            let knownPlayer = optionsPlayer
            let refreshOptions = updateCounter % 20 == 0
            pollingQueue.async { [weak self] in
                guard let self else { return }
                let newTrack = self.detectCurrentTrack()
                let sampledAt = Date()
                let player = newTrack?.player ?? .none
                let readsOptions = player != knownPlayer || refreshOptions
                var options: PlaybackOptions?
                if readsOptions && player != .none,
                   let response = try? Self.runPollingScript(self.optionsScript(for: player)) {
                    options = PlaybackOptions(response: response)
                }
                let sampledOptions = options
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.pollInFlight = false
                    guard generation == self.monitoringGeneration, self.timer != nil else { return }
                    self.applyPoll(newTrack, sampledAt: sampledAt,
                                   options: sampledOptions, readsOptions: readsOptions)
                }
            }
        }

        // 在两次真实位置更新之间进行插值预测
        if isCurrentlyPlaying {
            let elapsed = now.timeIntervalSince(lastUpdateTime)
            interpolatedPosition = lastRealPosition + elapsed
        } else {
            interpolatedPosition = lastRealPosition
        }
    }

    private func applyPoll(_ newTrack: TrackInfo?, sampledAt: Date,
                           options: PlaybackOptions?, readsOptions: Bool) {
        if let track = newTrack {
            lastRealPosition = track.position
            lastUpdateTime = sampledAt
            isCurrentlyPlaying = track.isPlaying
        } else {
            isCurrentlyPlaying = false
        }
        let trackChanged = newTrack?.lyricIdentity != currentTrack?.lyricIdentity
        // Publish a consistent position before the new track so it cannot select an old song's line.
        interpolatedPosition = lastRealPosition + (isCurrentlyPlaying ? Date().timeIntervalSince(sampledAt) : 0)
        currentTrack = newTrack
        let player = newTrack?.player ?? .none
        if readsOptions {
            if player != optionsPlayer { playbackControlError = nil }
            optionsPlayer = player
            playbackOptions = options
        }
        if trackChanged {
            currentLyrics = []
            if let track = newTrack {
                Task { await fetchLyrics(for: track) }
            }
        }
    }

    // NSAppleScript is main-thread-only. Run polling scripts in a child process
    // on the serial worker instead of moving NSAppleScript onto a background queue.
    static func runPollingScript(_ source: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "with timeout of 2 seconds\n\(source)\nend timeout"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timeout)
        defer { timeout.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LyricMist.Polling", code: result.contains("(-1743)") ? -1743 : -1)
        }
        return result
    }

    private func reportPollingError(_ error: Error, app: String) {
        guard (error as NSError).code == -1743 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasShownPermissionError else { return }
            self.hasShownPermissionError = true
            self.permissionError = "请在「系统设置 → 隐私与安全性 → 自动化」中允许 LyricMist 控制 \(app)"
        }
    }

    private func detectCurrentTrack() -> TrackInfo? {
        if let spotifyTrack = getSpotifyTrack() {
            return spotifyTrack
        }

        if let appleMusicTrack = getAppleMusicTrack() {
            return appleMusicTrack
        }

        return nil
    }

    private func getSpotifyTrack() -> TrackInfo? {
        let script = """
        tell application "Spotify"
            if it is running then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                set playerPos to player position
                set playerState to player state
                return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & trackDuration & "|||" & playerPos & "|||" & playerState
            else
                return "NOT_RUNNING"
            end if
        end tell
        """

        let resultString: String
        do {
            resultString = try Self.runPollingScript(script)
        } catch {
            reportPollingError(error, app: "Spotify")
            return nil
        }

        if resultString == "NOT_RUNNING" {
            return nil
        }

        let parts = resultString.components(separatedBy: "|||")
        guard parts.count >= 6 else {
            return nil
        }

        let trackName = parts[0]
        let trackArtist = parts[1]
        let trackAlbum = parts[2]
        let trackDuration = Double(parts[3]) ?? 0
        let playerPos = Double(parts[4]) ?? 0
        let isPlaying = parts[5] == "playing"

        return TrackInfo(
            title: trackName,
            artist: trackArtist,
            album: trackAlbum,
            duration: trackDuration / 1000.0,
            position: playerPos,
            isPlaying: isPlaying,
            player: .spotify
        )
    }

    private func getAppleMusicTrack() -> TrackInfo? {
        let script = """
        tell application "Music"
            if it is running then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                set playerPos to player position
                set playerState to player state
                return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & trackDuration & "|||" & playerPos & "|||" & playerState
            else
                return "NOT_RUNNING"
            end if
        end tell
        """

        let resultString: String
        do {
            resultString = try Self.runPollingScript(script)
        } catch {
            reportPollingError(error, app: "Music")
            return nil
        }

        if resultString == "NOT_RUNNING" {
            return nil
        }

        let parts = resultString.components(separatedBy: "|||")
        guard parts.count >= 6 else {
            return nil
        }

        let trackName = parts[0]
        let trackArtist = parts[1]
        let trackAlbum = parts[2]
        let trackDuration = Double(parts[3]) ?? 0
        let playerPos = Double(parts[4]) ?? 0
        let isPlaying = parts[5] == "playing"

        return TrackInfo(
            title: trackName,
            artist: trackArtist,
            album: trackAlbum,
            duration: trackDuration,
            position: playerPos,
            isPlaying: isPlaying,
            player: .appleMusic
        )
    }

    private func fetchLyrics(for track: TrackInfo) async {
        // 优先加载本地编辑的歌词
        if let editedLyrics = LyricStorage.shared.loadLyrics(title: track.title, artist: track.artist) {
            DispatchQueue.main.async {
                guard self.currentTrack?.lyricIdentity == track.lyricIdentity else { return }
                self.currentLyrics = editedLyrics
            }
            return
        }

        // 否则从在线获取
        let lyrics = await lyricFetcher.fetchLyrics(title: track.title, artist: track.artist)

        DispatchQueue.main.async {
            guard self.currentTrack?.lyricIdentity == track.lyricIdentity else { return }
            self.currentLyrics = lyrics
        }
    }

    // 公开方法：重新加载当前歌曲的歌词（用于重置时间偏移）
    func reloadCurrentLyrics() async {
        guard let track = currentTrack else { return }
        await fetchLyrics(for: track)
    }

    func refreshPlaybackOptions() {
        optionsPlayer = currentTrack?.player ?? .none
        guard optionsPlayer != .none else {
            playbackOptions = nil
            return
        }
        do {
            let result = try executePlaybackScript(optionsScript(for: optionsPlayer))
            playbackOptions = PlaybackOptions(response: result)
        } catch {
            // 读取失败时不保留上一个播放器的状态，也不反复弹出错误。
            playbackOptions = nil
        }
    }

    private func optionsScript(for player: MusicPlayer, command: String = "") -> String {
        let app = player == .spotify ? "Spotify" : "Music"
        return """
        tell application "\(app)"
            if not running then return "NOT_RUNNING"
            \(command)
            \(PlaybackOptions.readCommand(for: player))
        end tell
        """
    }

    func toggleShuffle() {
        guard let options = playbackOptions, options.canShuffle,
              let player = currentTrack?.player, player == optionsPlayer else { return }
        let property = player == .spotify ? "shuffling" : "shuffle enabled"
        changePlaybackOption("set \(property) to \(!options.shuffle ? "true" : "false")", for: player)
    }

    func cycleRepeatMode() {
        guard let options = playbackOptions, options.canRepeat,
              let player = currentTrack?.player, player == optionsPlayer else { return }
        setRepeatMode(options.repeatMode.next(for: player))
    }

    func setRepeatMode(_ mode: PlaybackRepeatMode) {
        guard let options = playbackOptions, options.canRepeat,
              let player = currentTrack?.player, player == optionsPlayer,
              player != .none, player != .spotify || mode != .one else { return }
        let command = player == .spotify
            ? "set repeating to \(mode != .off ? "true" : "false")"
            : "set song repeat to \(mode.rawValue)"
        changePlaybackOption(command, for: player)
    }

    private func changePlaybackOption(_ command: String, for player: MusicPlayer) {
        playbackControlError = nil
        do {
            let response = try executePlaybackScript(optionsScript(for: player, command: command))
            guard let options = PlaybackOptions(response: response) else {
                throw NSError(domain: "LyricMist.Playback", code: -1)
            }
            playbackOptions = options
        } catch {
            playbackOptions = nil
            playbackControlError = (error as NSError).code == -1743
                ? "请在系统设置 → 隐私与安全性 → 自动化中允许 LyricMist 控制播放器。"
                : "未能更改播放模式。请确认播放器正在运行，且当前播放内容支持此操作后重试。"
        }
    }

    func playPause() {
        guard let track = currentTrack else { return }

        let appName = track.player == .spotify ? "Spotify" : "Music"
        let script = "tell application \"\(appName)\" to playpause"

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("❌ PlayPause 错误: \(error)")
            }
        }
    }

    func nextTrack() {
        guard let track = currentTrack else { return }

        let appName = track.player == .spotify ? "Spotify" : "Music"
        let script = "tell application \"\(appName)\" to next track"

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("❌ NextTrack 错误: \(error)")
            }
        }
    }

    func previousTrack() {
        guard let track = currentTrack else { return }

        let appName = track.player == .spotify ? "Spotify" : "Music"
        let command = track.player == .spotify ? "previous track" : "back track"
        let script = "tell application \"\(appName)\" to \(command)"

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("❌ PreviousTrack 错误: \(error)")
            }
        }
    }
}

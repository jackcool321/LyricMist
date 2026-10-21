import SwiftUI

struct LyricView: View {
    // 暂时隐藏仍在开发中的歌词增强功能；保留实现，后续可直接改为 true 恢复。
    private enum FeatureVisibility {
        static let wordHighlightAnimation = false
        static let lyricEditingAndTimeline = false
    }

    /// 轻微提前时间轴，让歌词与听感更贴合。降低到 0.3 秒，配合更高的更新频率。
    private let lyricLeadTime: Double = 0.3

    @ObservedObject var musicManager: MusicPlayerManager
    @StateObject private var settings = StyleSettings.shared
    @State private var isHovered = false
    @State private var isLocked = false
    @State private var isEditingTime = false
    @State private var pendingControlExit: Task<Void, Never>?
    @State private var timeOffset: Double = 0.0

    var body: some View {
        ZStack {
            // 短句居中，长句在可用宽度内单行滚动
            lyricContent
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 控制栏层 - 浮动在歌词上方
            if isHovered || (isEditingTime && FeatureVisibility.lyricEditingAndTimeline) {
                controlBar
            }
        }
        .frame(minWidth: 160, minHeight: 120)
        .alert("播放控制失败", isPresented: Binding(
            get: { musicManager.playbackControlError != nil },
            set: { if !$0 { musicManager.playbackControlError = nil } }
        )) {
            Button("好", role: .cancel) { musicManager.playbackControlError = nil }
        } message: {
            Text(musicManager.playbackControlError ?? "")
        }
        .contentShape(Rectangle())
        .onChange(of: musicManager.currentTrack?.lyricIdentity) { _ in
            pendingControlExit?.cancel()
            pendingControlExit = nil
            timeOffset = 0
            isEditingTime = false
        }
        .onDisappear {
            pendingControlExit?.cancel()
            pendingControlExit = nil
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var controlBar: some View {
        VStack {
                    HStack(spacing: 6) {
                        if isEditingTime && FeatureVisibility.lyricEditingAndTimeline {
                            // 整组按钮共享悬停区域，跨过按钮间隙不会退出。
                            Button(action: {
                                adjustTime(0.5)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("0.5s")
                                        .monospacedDigit()
                                }
                                .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(ControlButtonStyle(width: 72))
                            .accessibilityLabel("歌词延后 0.5s")
                            .help("歌词延后 0.5s")

                            Button(action: {
                                resetTimeOffset()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .buttonStyle(ControlButtonStyle())
                            .accessibilityLabel("重置时间偏移")
                            .help("重置时间偏移")

                            Button(action: {
                                adjustTime(-0.5)
                            }) {
                                HStack(spacing: 4) {
                                    Text("0.5s")
                                        .monospacedDigit()
                                    Image(systemName: "chevron.right")
                                }
                                .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(ControlButtonStyle(width: 72))
                            .accessibilityLabel("歌词提前 0.5s")
                            .help("歌词提前 0.5s")

                        } else if isLocked {
                            Button(action: { isLocked = false }) {
                                Image(systemName: "lock.fill")
                            }
                            .buttonStyle(ControlButtonStyle())
                            .accessibilityLabel("解锁控制栏")
                            .help("解锁控制栏")
                        } else {
                            if settings.desktopWidth >= 210 {
                                Button(action: { musicManager.toggleShuffle() }) {
                                    Image(systemName: "shuffle")
                                }
                                .buttonStyle(ControlButtonStyle(isActive: musicManager.playbackOptions?.shuffle == true))
                                .disabled(musicManager.playbackOptions?.canShuffle != true)
                                .accessibilityLabel("随机播放")
                                .accessibilityValue(musicManager.playbackOptions?.shuffle == true ? "已开启" : "已关闭")
                                .help("随机播放")
                            }

                            Button(action: { musicManager.previousTrack() }) {
                                Image(systemName: "backward.fill")
                            }
                            .buttonStyle(ControlButtonStyle())
                            .disabled(musicManager.currentTrack == nil)
                            .accessibilityLabel("上一首")
                            .help("上一首")

                            Button(action: { musicManager.playPause() }) {
                                Image(systemName: musicManager.currentTrack?.isPlaying == true ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(ControlButtonStyle(isPrimary: true))
                            .disabled(musicManager.currentTrack == nil)
                            .accessibilityLabel(musicManager.currentTrack?.isPlaying == true ? "暂停" : "播放")
                            .help(musicManager.currentTrack?.isPlaying == true ? "暂停" : "播放")

                            Button(action: { musicManager.nextTrack() }) {
                                Image(systemName: "forward.fill")
                            }
                            .buttonStyle(ControlButtonStyle())
                            .disabled(musicManager.currentTrack == nil)
                            .accessibilityLabel("下一首")
                            .help("下一首")

                            if settings.desktopWidth >= 210 {
                                Button(action: { musicManager.cycleRepeatMode() }) {
                                    Image(systemName: musicManager.playbackOptions?.repeatMode == .one ? "repeat.1" : "repeat")
                                }
                                .buttonStyle(ControlButtonStyle(isActive: musicManager.playbackOptions.map { $0.repeatMode != .off } ?? false))
                                .disabled(musicManager.playbackOptions?.canRepeat != true)
                                .accessibilityLabel("循环播放")
                                .accessibilityValue(musicManager.playbackOptions?.repeatMode.title ?? "不可用")
                                .help(repeatHelp)
    
                                if FeatureVisibility.lyricEditingAndTimeline {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isEditingTime = true
                                        }
                                    }) {
                                        Image(systemName: "clock.arrow.2.circlepath")
                                    }
                                    .buttonStyle(ControlButtonStyle())
                                    .disabled(musicManager.currentTrack == nil || musicManager.currentLyrics.isEmpty)
                                    .accessibilityLabel("调整时间轴")
                                    .help("调整时间轴")
                                }
    
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isLocked = true
                                    }
                                }) {
                                    Image(systemName: "lock.open.fill")
                                }
                                .buttonStyle(ControlButtonStyle())
                                .accessibilityLabel("锁定控制栏")
                                .help("锁定控制栏")
                            }
                        }
                    }
            .font(.system(size: 11, weight: .medium))
            .padding(4)
            .background(Color.black.opacity(0.72), in: Capsule())
            .padding(.top, 8)
            .contentShape(Rectangle())
            .onHover(perform: handleControlHover)
            Spacer()
        }
        .transition(.opacity)
        .allowsHitTesting(true)
    }

    private var repeatHelp: String {
        guard let options = musicManager.playbackOptions, options.canRepeat,
              let player = musicManager.currentTrack?.player else { return "当前无法使用循环播放" }
        let hint = player == .spotify ? "；Spotify 支持关闭和列表循环" : ""
        return "当前：\(options.repeatMode.title)，点击切换\(hint)"
    }

    private func handleControlHover(_ hovering: Bool) {
        pendingControlExit?.cancel()
        pendingControlExit = nil
        guard !hovering, isEditingTime else { return }

        // 短暂离开边缘时保留模式；回到按钮区域会取消退出。
        pendingControlExit = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isEditingTime = false
            pendingControlExit = nil
        }
    }

    private var lyricContent: some View {
        Group {
            if let errorMessage = musicManager.permissionError {
                permissionErrorText(errorMessage)
            } else if let track = musicManager.currentTrack {
                if !musicManager.currentLyrics.isEmpty {
                    let lyricInfo = getCurrentLyricInfo()
                    if lyricInfo.text.isEmpty {
                        // 歌曲刚开始，还没到第一句歌词
                        trackInfoText(track: track)
                    } else {
                        // 有歌词文本，显示歌词
                        displayLyricText
                            .id(lyricInfo.text)  // 只在歌词文本变化时重建视图
                    }
                } else {
                    // 没有找到歌词文件
                    trackInfoText(track: track)
                }
            } else {
                placeholderText
            }
        }
    }

    private var displayLyricText: some View {
        let lyricInfo = getCurrentLyricInfo()
        return ScrollingDesktopLyric(progress: lyricInfo.progress) {
            Group {
                if FeatureVisibility.wordHighlightAnimation {
                    SmoothLyricText(
                        text: lyricInfo.text,
                        progress: lyricInfo.progress,
                        textColor: settings.textColor,
                        highlightColor: settings.highlightColor,
                        font: fontForSettings()
                    )
                } else {
                    Text(lyricInfo.text.replacingOccurrences(of: "\n", with: " "))
                        .font(fontForSettings())
                        .foregroundColor(settings.textColor)
                }
            }
        }
    }

    private func getCurrentLyricInfo() -> (text: String, progress: Double) {
        guard let track = musicManager.currentTrack else {
            return ("", 0.0)
        }

        // 使用插值后的位置，再加上提前量，确保平滑过渡
        let position = musicManager.interpolatedPosition + lyricLeadTime
        let lyrics = musicManager.currentLyrics

        guard !lyrics.isEmpty else {
            return ("", 0.0)
        }

        // 找到当前行和下一行
        var currentLine: LyricLine?
        var nextLine: LyricLine?

        for i in 0..<lyrics.count {
            if lyrics[i].time <= position {
                currentLine = lyrics[i]
                if i + 1 < lyrics.count {
                    nextLine = lyrics[i + 1]
                }
            } else {
                break
            }
        }

        guard let current = currentLine else {
            // 歌曲刚开始，还没到第一句歌词，返回空字符串
            return ("", 0.0)
        }

        // 计算当前行的进度
        let progress: Double
        if let next = nextLine {
            let lineDuration = next.time - current.time
            let elapsed = position - current.time
            // 防止异常歌词时间戳导致除零或 NaN，确保动画进度始终可插值。
            progress = lineDuration > 0
                ? min(1.0, max(0.0, elapsed / lineDuration))
                : 1.0
        } else {
            // 最后一行，继续显示当前歌词并保持完全高亮
            let elapsed = position - current.time
            let estimatedDuration = 5.0
            progress = min(1.0, max(0.0, elapsed / estimatedDuration))
        }

        return (current.text, progress)
    }

    private func trackInfoText(track: TrackInfo) -> some View {
        Text("\(track.title) - \(track.artist)")
            .font(fontForSettings())
            .foregroundColor(settings.textColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var placeholderText: some View {
        Text("没有正在播放的音乐")
            .font(fontForSettings())
            .foregroundColor(settings.textColor.opacity(0.6))
    }

    private func permissionErrorText(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.yellow)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(settings.textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button("打开系统设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 16)
    }

    private func fontForSettings() -> Font {
        let size = settings.fontSize

        switch settings.fontName {
        case "System":
            return .system(size: size)
        case "PingFang SC":
            return .custom("PingFangSC-Regular", size: size)
        case "Heiti SC":
            return .custom("STHeitiSC-Light", size: size)
        case "Songti SC":
            return .custom("STSongti-SC-Regular", size: size)
        case "Kaiti SC":
            return .custom("STKaitiSC-Regular", size: size)
        case "Yuanti SC":
            return .custom("STYuanti-SC-Regular", size: size)
        case "Arial Rounded":
            return .custom("Arial Rounded MT Bold", size: size)
        case "Helvetica Neue":
            return .custom("HelveticaNeue-Light", size: size)
        default:
            return .system(size: size)
        }
    }

    // 时间调整函数
    private func adjustTime(_ offset: Double) {
        timeOffset += offset
        // 每次只应用本次点击的增量。
        musicManager.currentLyrics = musicManager.currentLyrics.map { line in
            LyricLine(time: line.time + offset, text: line.text)
        }
        if let track = musicManager.currentTrack {
            saveTimeOffset(for: track)
        }
    }

    private func resetTimeOffset() {
        timeOffset = 0
        // 重新加载原始歌词
        if let track = musicManager.currentTrack {
            // 删除本地保存的偏移
            LyricStorage.shared.deleteLyrics(title: track.title, artist: track.artist)
            // 重新获取在线歌词
            Task {
                await musicManager.reloadCurrentLyrics()
            }
        }
    }

    private func saveTimeOffset(for track: TrackInfo) {
        // 保存带有时间偏移的歌词到本地
        LyricStorage.shared.saveLyrics(
            musicManager.currentLyrics,
            title: track.title,
            artist: track.artist
        )
    }
}

/// 以歌词时间轴驱动滚动，暂停时停止，跳转时直接定位；首尾各留 10% 阅读时间。
private struct ScrollingDesktopLyric<Content: View>: View {
    let progress: Double
    @ViewBuilder let content: () -> Content
    @State private var textWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let overflow = max(0, textWidth - geometry.size.width)
            let fraction = min(1, max(0, (progress - 0.1) / 0.8))
            content()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .background(GeometryReader { textGeometry in
                    Color.clear.preference(key: DesktopLyricWidthKey.self, value: textGeometry.size.width)
                })
                .offset(x: -overflow * fraction)
                .frame(width: geometry.size.width, height: geometry.size.height,
                       alignment: overflow > 0 ? .leading : .center)
                .clipped()
                .animation(reduceMotion ? nil : .linear(duration: 0.05), value: fraction)
                .onPreferenceChange(DesktopLyricWidthKey.self) { textWidth = $0 }
        }
    }
}

private struct DesktopLyricWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 用可动画的连续进度渲染逐字高亮，避免每次播放器轮询时整字跳变。
private struct SmoothLyricText: View, Animatable {
    let text: String
    var progress: Double
    let textColor: Color
    let highlightColor: Color
    let font: Font
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(highlightedText)
            .font(font)
        // 使用更短的动画时长，配合 20fps 的更新频率
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .linear(duration: 0.1),
            value: progress
        )
    }

    private var highlightedText: AttributedString {
        let characters = Array(text)
        let highlightPosition = min(1, max(0, progress)) * Double(characters.count)
        var result = AttributedString("")

        for (index, character) in characters.enumerated() {
            let amount = min(1, max(0, highlightPosition - Double(index)))
            // 使用更平滑的 smoothstep 缓动函数，让高亮过渡更自然
            let easedAmount = amount * amount * (3 - 2 * amount)
            var characterString = AttributedString(String(character))
            let color = NSColor(textColor).blended(
                withFraction: CGFloat(easedAmount), of: NSColor(highlightColor)
            ) ?? NSColor(textColor)
            characterString.foregroundColor = Color(nsColor: color)
            result.append(characterString)
        }

        return result
    }
}

struct ControlButtonStyle: ButtonStyle {
    var width: CGFloat = 26
    var isPrimary = false
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .fixedSize()
            .frame(width: width, height: 26)
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.24 : ((isPrimary || isActive) ? 0.12 : 0)))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

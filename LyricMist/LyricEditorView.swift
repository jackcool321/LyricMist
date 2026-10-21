import SwiftUI

/// 歌词编辑器视图
struct LyricEditorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var musicManager: MusicPlayerManager

    let trackTitle: String
    let trackArtist: String

    @State private var editableLyrics: [EditableLyricLine] = []
    @State private var timeOffset: Double = 0.0
    @State private var showingSaveConfirmation = false
    @State private var selectedLineIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerView

            Divider()

            // 时间偏移控制
            timeOffsetControl

            Divider()

            // 歌词列表
            lyricList

            Divider()

            // 底部操作栏
            footerView
        }
        .frame(width: 700, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadLyrics()
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("编辑歌词")
                    .font(.headline)
                Text("\(trackTitle) - \(trackArtist)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var timeOffsetControl: some View {
        VStack(spacing: 8) {
            HStack {
                Text("时间轴整体偏移")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "%+.2fs", timeOffset))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(timeOffset == 0 ? .secondary : .blue)
            }

            HStack(spacing: 12) {
                Button("← 0.5s") {
                    adjustTimeOffset(0.5)
                }
                .buttonStyle(.bordered)

                Button("← 0.1s") {
                    adjustTimeOffset(0.1)
                }
                .buttonStyle(.bordered)

                Slider(value: $timeOffset, in: -5.0...5.0, step: 0.01)
                    .frame(maxWidth: 200)

                Button("0.1s →") {
                    adjustTimeOffset(-0.1)
                }
                .buttonStyle(.bordered)

                Button("0.5s →") {
                    adjustTimeOffset(-0.5)
                }
                .buttonStyle(.bordered)

                Button("重置") {
                    timeOffset = 0.0
                }
                .buttonStyle(.bordered)
                .disabled(timeOffset == 0)
            }

            Text("提示：负值表示歌词提前，正值表示歌词延后")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var lyricList: some View {
        ScrollViewReader { proxy in
            List(editableLyrics.indices, id: \.self, selection: $selectedLineIndex) { index in
                lyricRow(at: index)
                    .id(index)
            }
            .listStyle(.plain)
            .onChange(of: musicManager.interpolatedPosition) { _ in
                highlightCurrentLine(proxy: proxy)
            }
        }
    }

    private func lyricRow(at index: Int) -> some View {
        let line = editableLyrics[index]
        let adjustedTime = line.time + timeOffset
        let isCurrent = isCurrentLine(index)

        return HStack(spacing: 12) {
            // 时间轴
            TextField("", value: Binding(
                get: { adjustedTime },
                set: { newValue in
                    editableLyrics[index].time = newValue - timeOffset
                }
            ), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .font(.system(.body, design: .monospaced))

            Text(formatTime(adjustedTime))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            // 歌词文本
            TextField("歌词内容", text: $editableLyrics[index].text)
                .textFieldStyle(.roundedBorder)

            // 删除按钮
            Button(action: {
                deleteLine(at: index)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("删除此行")
        }
        .padding(.vertical, 4)
        .background(isCurrent ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }

    private var footerView: some View {
        HStack {
            Button("添加歌词行") {
                addNewLine()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("恢复在线歌词") {
                restoreOnlineLyrics()
            }
            .buttonStyle(.bordered)

            Button("保存") {
                saveLyrics()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - 数据操作

    private func loadLyrics() {
        // 优先加载本地编辑的歌词
        if let stored = LyricStorage.shared.loadLyrics(title: trackTitle, artist: trackArtist) {
            editableLyrics = stored.map { EditableLyricLine(time: $0.time, text: $0.text) }
        } else {
            // 否则使用当前在线歌词
            editableLyrics = musicManager.currentLyrics.map {
                EditableLyricLine(time: $0.time, text: $0.text)
            }
        }
    }

    private func saveLyrics() {
        let finalLyrics = editableLyrics.map { line in
            LyricLine(time: line.time + timeOffset, text: line.text)
        }.sorted { $0.time < $1.time }

        LyricStorage.shared.saveLyrics(finalLyrics, title: trackTitle, artist: trackArtist)

        // 立即更新播放器的歌词
        DispatchQueue.main.async {
            musicManager.currentLyrics = finalLyrics
        }

        showingSaveConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showingSaveConfirmation = false
            dismiss()
        }
    }

    private func restoreOnlineLyrics() {
        LyricStorage.shared.deleteLyrics(title: trackTitle, artist: trackArtist)

        // 重新获取在线歌词
        Task {
            if let track = musicManager.currentTrack {
                let lyrics = await LyricFetcher().fetchLyrics(title: track.title, artist: track.artist)
                DispatchQueue.main.async {
                    musicManager.currentLyrics = lyrics
                    dismiss()
                }
            }
        }
    }

    private func addNewLine() {
        let newTime = editableLyrics.last?.time ?? 0.0 + 5.0
        editableLyrics.append(EditableLyricLine(time: newTime, text: ""))
    }

    private func deleteLine(at index: Int) {
        guard editableLyrics.count > 1 else { return }
        editableLyrics.remove(at: index)
    }

    private func adjustTimeOffset(_ delta: Double) {
        timeOffset += delta
    }

    // MARK: - 辅助方法

    private func isCurrentLine(_ index: Int) -> Bool {
        let position = musicManager.interpolatedPosition
        let lyrics = editableLyrics.map { LyricLine(time: $0.time + timeOffset, text: $0.text) }

        guard index < lyrics.count else { return false }

        for i in 0..<lyrics.count {
            if lyrics[i].time <= position {
                if i == index {
                    return true
                }
            } else {
                break
            }
        }

        return false
    }

    private func highlightCurrentLine(proxy: ScrollViewProxy) {
        let position = musicManager.interpolatedPosition
        let lyrics = editableLyrics.map { LyricLine(time: $0.time + timeOffset, text: $0.text) }

        for i in 0..<lyrics.count {
            if lyrics[i].time <= position {
                if i + 1 < lyrics.count && lyrics[i + 1].time > position {
                    withAnimation {
                        proxy.scrollTo(i, anchor: .center)
                    }
                    break
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, secs, millis)
    }
}

/// 可编辑的歌词行
struct EditableLyricLine: Identifiable {
    let id = UUID()
    var time: Double
    var text: String
}

// MARK: - 预览
struct LyricEditorView_Previews: PreviewProvider {
    static var previews: some View {
        LyricEditorView(
            musicManager: MusicPlayerManager(),
            trackTitle: "示例歌曲",
            trackArtist: "示例歌手"
        )
    }
}

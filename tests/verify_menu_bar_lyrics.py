"""Check production menu-bar text selection without launching a music player."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / 'LyricMist/LyricMistApp.swift').read_text()
manager = (root / 'LyricMist/MusicPlayerManager.swift').read_text()
start = app.index('    static func menuBarText(')
end = app.index('\n    private func updateLyricPresentation', start)
models = manager[manager.index('enum MusicPlayer'):manager.index('enum PlaybackRepeatMode')]
swift = 'import Foundation\n' + models + '''
struct LyricLine { let time: Double; let text: String }
struct Presentation {
''' + app[start:end] + '''
}
let track = TrackInfo(title: "Song", artist: "Artist", album: "Album",
                      duration: 100, position: 0, isPlaying: false, player: .spotify)
let lyrics = [LyricLine(time: 10, text: "First"),
              LyricLine(time: 20, text: "Second"),
              LyricLine(time: 30, text: " ")]
func check(_ time: Double, _ expected: String, _ name: String) {
    precondition(Presentation.menuBarText(track: track, lyrics: lyrics, position: time) == expected, name)
    print("PASS: \\(name)")
}
check(0, "Song - Artist", "intro falls back to track")
check(9.71, "First", "matches desktop lead time")
check(20, "Second", "next lyric and paused playback")
check(11, "First", "backward seek")
check(31, "Song - Artist", "blank lyric fallback")
precondition(Presentation.menuBarText(track: nil, lyrics: lyrics, position: 20) == "没有正在播放的音乐")
precondition(Presentation.menuBarText(track: track, lyrics: [], position: 20) == "Song - Artist")
print("PASS: no player and no lyrics")
'''
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'main.swift'
    binary = Path(directory) / 'verify'
    source.write_text(swift)
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/lyricmist-test-module-cache', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

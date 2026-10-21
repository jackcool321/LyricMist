"""Run production timing methods with deterministic playback fixtures."""
from pathlib import Path
import subprocess, tempfile, re
root = Path(__file__).resolve().parents[1]
manager = (root / 'LyricMist/MusicPlayerManager.swift').read_text()
view = (root / 'LyricMist/LyricView.swift').read_text()
# Verify arrow bindings as well as the underlying delta calculation.
left = re.search(r'Button\(action: \{\s*adjustTime\(([-\d.]+)\).*?chevron.left', view, re.S)
right = re.search(r'Button\(action: \{\s*adjustTime\(([-\d.]+)\)\s*\}\) \{\s*HStack\(spacing: 4\) \{\s*Text\("0.5s"\).*?chevron.right', view, re.S)
assert left and float(left[1]) == 0.5, 'Left arrow must delay lyrics'
assert right and float(right[1]) == -0.5, 'Right arrow must advance lyrics'
print('PASS: left delays / right advances by 0.5s', flush=True)
def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
track = manager[manager.index('enum MusicPlayer'):manager.index('class MusicPlayerManager')]
identity = 'newTrack?.lyricIdentity != currentTrack?.lyricIdentity' if 'let trackChanged = newTrack?.lyricIdentity' in manager else 'newTrack != currentTrack'
adjust = block(view, 'private func adjustTime(').replace('private ', '')
apply = block(view, 'private func applyTimeOffset(').replace('private ', '') if 'private func applyTimeOffset(' in view else ''
swift = '''import Foundation
''' + track + '''
struct LyricLine { let time: Double; let text: String }
class MockManager { var currentTrack: TrackInfo? = nil; var currentLyrics = [LyricLine(time: 10, text: "歌词")] }
class Harness {
var timeOffset = 0.0
let musicManager = MockManager()
func saveTimeOffset(for track: TrackInfo) {}
''' + adjust + '\n' + apply + '''
}
func track(_ position: Double, title: String = "歌曲", playing: Bool = true) -> TrackInfo {
TrackInfo(title: title, artist: "歌手", album: "专辑", duration: 180, position: position, isPlaying: playing, player: .spotify)
}
var failures = 0
func check(_ value: Bool, _ name: String) {
print("\\(value ? "PASS" : "FAIL"): \\(name)")
if !value { failures += 1 }
}
var currentTrack: TrackInfo? = track(10)
var newTrack: TrackInfo? = track(10.2)
check(!(''' + identity + '''), "playback polling must not reload adjusted lyrics")
newTrack = track(10.2, playing: false)
check(!(''' + identity + '''), "pause must not reload adjusted lyrics")
newTrack = track(0, title: "下一首")
check(''' + identity + ''', "new song must reload lyrics")
let h = Harness()
h.adjustTime(0.5)
h.adjustTime(0.5)
check(h.musicManager.currentLyrics[0].time == 11, "two clicks shift exactly 1s")
h.adjustTime(-0.5)
h.adjustTime(-0.5)
check(h.musicManager.currentLyrics[0].time == 10, "opposite clicks cancel")
exit(failures == 0 ? 0 : 1)
'''
with tempfile.TemporaryDirectory() as tmp:
    source = Path(tmp) / 'main.swift'
    source.write_text(swift)
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/lyricmist-test-cache', str(source), '-o', tmp + '/test'], check=True)
    raise SystemExit(subprocess.run([tmp + '/test']).returncode)

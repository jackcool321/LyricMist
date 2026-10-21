"""Exercise the production manager with a fake AppleScript transport."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
source = (root / 'LyricMist/MusicPlayerManager.swift').read_text()
harness = r'''
struct LyricLine { let time: Double; let text: String }
class LyricFetcher {
    func fetchLyrics(title: String, artist: String) async -> [LyricLine] { [] }
}
class LyricStorage {
    static let shared = LyricStorage()
    func loadLyrics(title: String, artist: String) -> [LyricLine]? { nil }
}
func check(_ condition: Bool, _ name: String) {
    guard condition else { fatalError(name) }
    print("PASS: \(name)")
}
func track(_ player: MusicPlayer) -> TrackInfo {
    TrackInfo(title: "Song", artist: "Artist", album: "Album", duration: 180,
              position: 10, isPlaying: true, player: player)
}
var response = "false|||off|||true|||true"
var commands: [String] = []
var failure = false
let manager = MusicPlayerManager { script in
    commands.append(script)
    if failure { throw NSError(domain: "test", code: -1743) }
    return response
}
manager.toggleShuffle()
manager.cycleRepeatMode()
check(commands.isEmpty, "no player: commands are ignored")
manager.currentTrack = track(.appleMusic)
manager.refreshPlaybackOptions()
for (reply, command, expected) in [
    ("false|||all|||true|||true", "set song repeat to all", PlaybackRepeatMode.all),
    ("false|||one|||true|||true", "set song repeat to one", .one),
    ("false|||off|||true|||true", "set song repeat to off", .off)
] {
    response = reply
    manager.cycleRepeatMode()
    check(commands.last!.contains(command) && manager.playbackOptions?.repeatMode == expected,
          "Music repeat cycle: \(expected)")
}
response = "true|||off|||true|||true"
manager.toggleShuffle()
check(commands.last!.contains("set shuffle enabled to true") && manager.playbackOptions?.shuffle == true,
      "Music shuffle enables and reads back")
response = "false|||off|||true|||true"
manager.toggleShuffle()
check(commands.last!.contains("set shuffle enabled to false") && manager.playbackOptions?.shuffle == false,
      "Music shuffle disables")
manager.currentTrack = track(.spotify)
let beforeSwitch = commands.count
manager.toggleShuffle()
check(commands.count == beforeSwitch, "player switch cannot use stale options")
manager.refreshPlaybackOptions()
response = "false|||all|||true|||true"
manager.cycleRepeatMode()
check(commands.last!.contains("set repeating to true"), "Spotify repeat on")
response = "false|||off|||true|||true"
manager.cycleRepeatMode()
check(commands.last!.contains("set repeating to false"), "Spotify repeat off skips single-track mode")
response = "true|||all|||true|||true"
manager.toggleShuffle()
check(commands.last!.contains("set shuffling to true"), "Spotify shuffle uses its own property")
manager.refreshPlaybackOptions()
check(manager.playbackOptions?.repeatMode == .all, "external repeat change synchronizes")
response = "false|||off|||false|||false"
manager.refreshPlaybackOptions()
let beforeDisabled = commands.count
manager.toggleShuffle()
manager.cycleRepeatMode()
check(commands.count == beforeDisabled, "unsupported context blocks commands")
response = "false|||off|||true|||true"
manager.refreshPlaybackOptions()
failure = true
manager.toggleShuffle()
check(manager.playbackOptions == nil && manager.playbackControlError?.contains("自动化") == true,
      "permission failure clears stale state and explains recovery")
failure = false
response = "NOT_RUNNING"
manager.refreshPlaybackOptions()
check(manager.playbackOptions == nil, "closed player clears state")
response = "true|||all|||true|||true"
manager.refreshPlaybackOptions()
manager.currentTrack = nil
manager.refreshPlaybackOptions()
check(manager.playbackOptions == nil, "no track clears state")
for invalid in ["", "true|||unknown|||true|||true", "maybe|||off|||true|||true", "true|||off"] {
    check(PlaybackOptions(response: invalid) == nil, "malformed state rejected: \(invalid)")
}
response = "false|||off|||true|||true"
manager.currentTrack = track(.appleMusic)
manager.refreshPlaybackOptions()
response = "false|||one|||true|||true"
manager.setRepeatMode(.one)
check(commands.last!.contains("set song repeat to one") && manager.playbackOptions?.repeatMode == .one,
      "menu selects single-track repeat directly")
manager.currentTrack = track(.spotify)
response = "false|||off|||true|||true"
manager.refreshPlaybackOptions()
let beforeUnsupportedMode = commands.count
manager.setRepeatMode(.one)
check(commands.count == beforeUnsupportedMode, "Spotify rejects unsupported single-track selection")
// Compile scripts against installed dictionaries without executing playback commands.
for player in [MusicPlayer.spotify, .appleMusic] {
    let app = player == .spotify ? "Spotify" : "Music"
    let commands = player == .spotify
        ? ["set shuffling to true", "set repeating to false"]
        : ["set shuffle enabled to true", "set song repeat to all", "set song repeat to one", "set song repeat to off"]
    for command in commands {
        let script = NSAppleScript(source: "tell application \"\(app)\"\nif not running then return \"NOT_RUNNING\"\n\(command)\n\(PlaybackOptions.readCommand(for: player))\nend tell")!
        var error: NSDictionary?
        check(script.compileAndReturnError(&error), "AppleScript compiles: \(app) \(command); \(String(describing: error))")
    }
}
'''
if '--logic-only' in sys.argv:
    harness = harness.split('// Compile scripts against installed dictionaries')[0]
    print('Skipping AppleScript dictionary checks (--logic-only)', flush=True)

with tempfile.TemporaryDirectory() as tmp:
    main = Path(tmp) / 'main.swift'
    main.write_text(source + '\n' + harness)
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/lyricmist-test-cache', str(main), '-o', tmp + '/test'], check=True)
    subprocess.run([tmp + '/test'], check=True)

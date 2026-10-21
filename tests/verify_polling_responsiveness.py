"""A slow player query must not stall the UI run loop or overlap another query."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'LyricMist/MusicPlayerManager.swift').read_text()
# Isolate transport, retaining the real timer, scheduling and state publication.
def replace_body(source, marker, body):
    start = source.index('{', source.index(marker))
    end, depth = start + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[:start+1] + body + source[end-1:]
source = replace_body(source, 'private func requestPermissions()', '')
source = replace_body(source, 'private func detectCurrentTrack()', '''
    probeLock.lock()
    inFlight += 1
    maximumInFlight = max(maximumInFlight, inFlight)
    probeLock.unlock()
    Thread.sleep(forTimeInterval: 0.35)
    probeLock.lock()
    inFlight -= 1
    queryCount += 1
    probeLock.unlock()
    return nil
''')
harness = r'''
let probeLock = NSLock()
var inFlight = 0
var maximumInFlight = 0
var queryCount = 0
struct LyricLine { let time: Double; let text: String }
class LyricFetcher {
    func fetchLyrics(title: String, artist: String) async -> [LyricLine] { [] }
}
class LyricStorage {
    static let shared = LyricStorage()
    func loadLyrics(title: String, artist: String) -> [LyricLine]? { nil }
}
let manager = MusicPlayerManager()
var previous = ProcessInfo.processInfo.systemUptime
var maximumGap = 0.0
let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
    let now = ProcessInfo.processInfo.systemUptime
    maximumGap = max(maximumGap, now - previous)
    previous = now
}
manager.startMonitoring()
RunLoop.main.run(until: Date().addingTimeInterval(1.6))
manager.stopMonitoring()
heartbeat.invalidate()
let sentinel = TrackInfo(title: "Stopped", artist: "Test", album: "", duration: 10,
                         position: 0, isPlaying: false, player: .spotify)
manager.currentTrack = sentinel
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
precondition(manager.currentTrack == sentinel, "late results must be discarded after stop")
print("PASS: late query result cannot overwrite stopped state")
print("UI maximum heartbeat gap: \(Int(maximumGap * 1000)) ms")
probeLock.lock()
let count = queryCount
let concurrent = maximumInFlight
probeLock.unlock()
guard maximumGap < 0.08, count >= 2, concurrent == 1 else {
    print("FAIL: blocking/overlapping player queries (queries=\(count), concurrent=\(concurrent))")
    exit(1)
}
print("PASS: 350 ms player responses do not block UI or overlap")
'''
with tempfile.TemporaryDirectory() as directory:
    swift = Path(directory) / 'main.swift'
    binary = Path(directory) / 'verify'
    swift.write_text(source + '\n' + harness)
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/lyricmist-test-module-cache', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

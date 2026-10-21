"""Exercise the production AppKit marquee without launching a player."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'LyricMist/LyricMistApp.swift').read_text()
view = source[source.index('final class MenuBarLyricView'):]
harness = r'''
let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 24),
                      styleMask: [.borderless], backing: .buffered, defer: false)
let view = MenuBarLyricView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
window.contentView = view
let text = "这是一句足够长的歌词，用于验证流畅滚动与无缝循环"
view.configure(text: text, visible: true)
view.layoutSubtreeIfNeeded()
let track = view.layer!.sublayers!.first!
if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
    let animation = track.animation(forKey: "lyricScroll") as! CABasicAnimation
    let distance = -(animation.toValue as! CGFloat)
    let copies = track.sublayers!
    // At the wrap, the incoming copy and the initial copy occupy the same point.
    precondition(abs(copies[1].frame.minX - distance - copies[0].frame.minX) < 0.001)
    precondition(animation.repeatCount == .infinity)
    precondition(abs(animation.duration - Double(distance) / 24) < 0.001)
    view.configure(text: text, visible: true)
    let unchanged = track.animation(forKey: "lyricScroll") as! CABasicAnimation
    precondition(unchanged.beginTime == animation.beginTime, "polling must not restart animation")
    print("PASS: compositor animation, seamless wrap, constant speed, no polling resets")
} else {
    precondition(track.animation(forKey: "lyricScroll") == nil)
    print("PASS: reduced motion disables continuous movement")
}
view.configure(text: "短歌词", visible: true)
precondition(track.animation(forKey: "lyricScroll") == nil)
view.configure(text: text, visible: false)
precondition(track.animation(forKey: "lyricScroll") == nil)
precondition(view.hitTest(.zero) == nil)
print("PASS: short lyrics and hiding stop animation; clicks pass through")
'''
with tempfile.TemporaryDirectory() as directory:
    swift = Path(directory) / 'main.swift'
    binary = Path(directory) / 'verify'
    swift.write_text('import SwiftUI\n' + view + '\n' + harness)
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/lyricmist-test-module-cache', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

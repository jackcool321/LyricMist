import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDirectory = CommandLine.arguments.dropFirst().first ?? "/private/tmp/lyricmist-icons"
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

func drawIcon(size: Int) -> NSImage {
    let canvas = CGFloat(size)
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocusFlipped(false)

    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: canvas, height: canvas), xRadius: canvas * 0.219, yRadius: canvas * 0.219).fill()

    let noteSize = canvas * 0.51
    let configuration = NSImage.SymbolConfiguration(pointSize: noteSize, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
        let symbolRect = NSRect(x: (canvas - noteSize) / 2, y: (canvas - noteSize) / 2 + canvas * 0.01, width: noteSize, height: noteSize)
        NSColor.black.set()
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    image.unlockFocus()
    return image
}

for size in sizes {
    let image = drawIcon(size: size)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else { continue }
    try pngData.write(to: URL(fileURLWithPath: "\(outputDirectory)/icon_\(size).png"))
}

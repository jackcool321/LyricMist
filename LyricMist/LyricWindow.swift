import AppKit
import SwiftUI
import Combine

class LyricWindow {
    private var window: NSWindow?
    private var widthSubscription: AnyCancellable?
    private let musicManager: MusicPlayerManager

    init(musicManager: MusicPlayerManager) {
        self.musicManager = musicManager
        setupWindow()
    }

    private func setupWindow() {
        let contentView = LyricView(musicManager: musicManager)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: StyleSettings.shared.desktopWidth, height: 140),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window?.isMovableByWindowBackground = true
        window?.contentView = NSHostingView(rootView: contentView)
        window?.hasShadow = false

        if let savedFrame = UserDefaults.standard.string(forKey: "LyricWindowFrame") {
            let frame = NSRectFromString(savedFrame)
            window?.setFrame(frame, display: true)
        } else {
            centerWindow()
        }

        updateWidth(StyleSettings.shared.desktopWidth)
        widthSubscription = StyleSettings.shared.$desktopWidth
            .dropFirst()
            .sink { [weak self] width in self?.updateWidth(width) }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.saveWindowPosition()
        }
    }

    private func updateWidth(_ width: Double) {
        guard let window else { return }
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        var frame = window.frame
        let newWidth = min(CGFloat(width), screen?.width ?? CGFloat(width))
        frame.origin.x += (frame.width - newWidth) / 2
        frame.size = NSSize(width: newWidth, height: 140)
        if let screen {
            frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - frame.width))
            frame.origin.y = max(screen.minY, min(frame.origin.y, screen.maxY - frame.height))
        }
        window.setFrame(frame, display: true)
        saveWindowPosition()
    }

    private func centerWindow() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let windowRect = window?.frame ?? .zero

        let x = screenRect.midX - windowRect.width / 2
        let y = screenRect.maxY - windowRect.height - 100

        window?.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func saveWindowPosition() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "LyricWindowFrame")
    }

    func showWindow() {
        window?.orderFrontRegardless()
    }

    func hideWindow() {
        window?.orderOut(nil)
    }

    func toggleWindow() {
        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }
}

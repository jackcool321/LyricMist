import SwiftUI
import Combine

@main
struct LyricMistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var lyricWindow: LyricWindow?
    var musicManager: MusicPlayerManager?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var lyricsVisible = true
    private let scrollingLyrics = MenuBarLyricView(frame: .zero)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Xcode and direct executable launches can bypass Launch Services reuse.
        // Elect the earliest process before creating any menu item or lyric window.
        if let bundleID = Bundle.main.bundleIdentifier {
            let current = NSRunningApplication.current
            let primary = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { !$0.isTerminated }
                .min {
                    let lhs = $0.launchDate ?? .distantFuture
                    let rhs = $1.launchDate ?? .distantFuture
                    return lhs == rhs ? $0.processIdentifier < $1.processIdentifier : lhs < rhs
                }
            if let primary, primary.processIdentifier != current.processIdentifier {
                primary.activate(options: [.activateIgnoringOtherApps])
                NSApp.terminate(nil)
                return
            }
        }
        setupMenuBar()

        // 延迟请求权限，确保应用完全启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            PermissionManager.shared.requestAutomationPermissions()
        }

        musicManager = MusicPlayerManager()
        lyricWindow = LyricWindow(musicManager: musicManager!)

        observeLyricPresentation()
        musicManager?.startMonitoring()

        // 检查权限状态，5秒后如果仍有错误则显示说明
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.musicManager?.permissionError != nil {
                PermissionManager.shared.showPermissionInstructions()
            }
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Keep the menu-bar entry visible even when the optional asset is missing.
            let image = NSImage(named: "MusicNote") ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "LyricMist")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "LyricMist"
            scrollingLyrics.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(scrollingLyrics)
            NSLayoutConstraint.activate([
                scrollingLyrics.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 8),
                scrollingLyrics.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
                scrollingLyrics.topAnchor.constraint(equalTo: button.topAnchor),
                scrollingLyrics.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "显示歌词", action: #selector(showLyrics), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "隐藏歌词", action: #selector(hideLyrics), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "权限设置", action: #selector(openPermissionSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func showLyrics() {
        lyricsVisible = true
        updateLyricPresentation()
    }

    @objc func hideLyrics() {
        lyricsVisible = false
        updateLyricPresentation()
    }

    private func observeLyricPresentation() {
        // @Published emits before mutation; deliver after the stored value changes.
        StyleSettings.shared.$displayMode.combineLatest(StyleSettings.shared.$menuBarWidth)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLyricPresentation() }
            .store(in: &subscriptions)

        guard let musicManager else { return }
        musicManager.$currentTrack.combineLatest(musicManager.$currentLyrics, musicManager.$interpolatedPosition)
            .map { track, lyrics, position in
                Self.menuBarText(track: track, lyrics: lyrics, position: position)
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] text in self?.updateMenuBarText(text) }
            .store(in: &subscriptions)
        updateLyricPresentation()
    }

    static func menuBarText(track: TrackInfo?, lyrics: [LyricLine], position: Double) -> String {
        guard let track else { return "没有正在播放的音乐" }
        if let line = lyrics.last(where: { $0.time <= position + 0.3 }),
           !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return line.text
        }
        return "\(track.title) - \(track.artist)"
    }

    private func updateLyricPresentation() {
        let settings = StyleSettings.shared
        if lyricsVisible && settings.displayMode == .desktop {
            lyricWindow?.showWindow()
        } else {
            lyricWindow?.hideWindow()
        }

        guard let statusItem, let button = statusItem.button else { return }
        let showsText = lyricsVisible && settings.displayMode == .menuBar
        statusItem.length = showsText ? CGFloat(settings.menuBarWidth) : NSStatusItem.variableLength
        button.imagePosition = showsText ? .noImage : .imageOnly
        button.font = .menuBarFont(ofSize: 0)
        button.alignment = .left
        updateMenuBarText(Self.menuBarText(
            track: musicManager?.currentTrack,
            lyrics: musicManager?.currentLyrics ?? [],
            position: musicManager?.interpolatedPosition ?? 0
        ))
    }

    private func updateMenuBarText(_ text: String) {
        guard let button = statusItem?.button else { return }
        let showsText = lyricsVisible && StyleSettings.shared.displayMode == .menuBar
        button.title = ""
        scrollingLyrics.configure(text: text, visible: showsText)
        button.toolTip = showsText ? text : "LyricMist"
        button.setAccessibilityLabel(showsText ? "LyricMist：\(text)" : "LyricMist")
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "LyricMist 设置"
            window.contentView = NSHostingView(rootView: ContentView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openPermissionSettings() {
        PermissionManager.shared.showPermissionInstructions()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

/// Render text once; Core Animation moves the layers independently of player polling.
final class MenuBarLyricView: NSView {
    private(set) var text = ""
    private let trackLayer = CALayer()
    private let firstText = CATextLayer()
    private let repeatedText = CATextLayer()
    private let font = NSFont.menuBarFont(ofSize: 0)
    private var renderedSize = CGSize.zero
    private var accessibilityObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(trackLayer)
        for textLayer in [firstText, repeatedText] {
            textLayer.font = font.fontName as CFString
            textLayer.fontSize = font.pointSize
            textLayer.isWrapped = false
            textLayer.truncationMode = .none
            trackLayer.addSublayer(textLayer)
        }
        setAccessibilityElement(false)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Keep the original status button responsible for clicks and accessibility.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(text: String, visible: Bool) {
        guard self.text != text || isHidden == visible else { return }
        self.text = text
        isHidden = !visible
        rebuild()
    }

    override func layout() {
        super.layout()
        if renderedSize != bounds.size { rebuild() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuild()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            firstText.foregroundColor = NSColor.labelColor.cgColor
            repeatedText.foregroundColor = NSColor.labelColor.cgColor
            CATransaction.commit()
        }
    }

    // The second copy is exactly one cycle ahead, so wrapping never jumps visually.
    static func cycleDistance(textWidth: CGFloat) -> CGFloat { ceil(textWidth) + 40 }

    private func rebuild() {
        renderedSize = bounds.size
        trackLayer.removeAnimation(forKey: "lyricScroll")
        let size = (text as NSString).size(withAttributes: [.font: font])
        let width = ceil(size.width)
        let distance = Self.cycleDistance(textWidth: width)
        let canScroll = !isHidden && window != nil && bounds.width > 0 && width > bounds.width
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        trackLayer.transform = CATransform3DIdentity
        for (index, textLayer) in [firstText, repeatedText].enumerated() {
            textLayer.string = text
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.frame = CGRect(x: CGFloat(index) * distance,
                                     y: floor((bounds.height - ceil(size.height)) / 2),
                                     width: width, height: ceil(size.height))
        }
        repeatedText.isHidden = !canScroll
        CATransaction.commit()
        updateColors()

        guard canScroll else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -distance
        animation.duration = Double(distance) / 24
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.repeatCount = .infinity
        animation.beginTime = trackLayer.convertTime(CACurrentMediaTime(), from: nil) + 0.8
        if #available(macOS 12.0, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        trackLayer.add(animation, forKey: "lyricScroll")
    }

    deinit {
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }
}

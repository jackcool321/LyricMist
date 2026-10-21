import SwiftUI

struct ContentView: View {
    @StateObject private var settings = StyleSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("歌词展示")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(alignment: .top, spacing: 12) {
                    Text("展示位置")
                        .frame(width: 80, alignment: .leading)
                    DisplayModePicker(selection: $settings.displayMode)
                        .frame(height: 54)
                }

                if settings.displayMode == .desktop {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("展示宽度")
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $settings.desktopWidth, in: StyleSettings.desktopWidthRange, step: 10)
                                .accessibilityLabel("桌面歌词展示宽度")
                            Text("\(Int(settings.desktopWidth))")
                                .monospacedDigit()
                                .frame(width: 40)
                        }
                        Text("超出展示宽度的歌词将单行滚动，不换行")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.displayMode == .menuBar {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("展示宽度")
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $settings.menuBarWidth, in: 100...300, step: 1)
                                .accessibilityLabel("菜单栏歌词展示宽度")
                            Text("\(Int(settings.menuBarWidth))")
                                .monospacedDigit()
                                .frame(width: 40)
                        }
                        Text("请确保菜单栏宽度足够，避免被系统隐藏")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text("桌面歌词样式")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text("歌词大小")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $settings.fontSize, in: 12...72, step: 1)
                        Text("\(Int(settings.fontSize))")
                            .frame(width: 40)
                    }

                    HStack {
                        Text("字体")
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $settings.fontName) {
                            Text("系统默认").tag("System")
                            Text("苹方").tag("PingFang SC")
                            Text("黑体").tag("Heiti SC")
                            Text("宋体").tag("Songti SC")
                            Text("楷体").tag("Kaiti SC")
                            Text("圆体").tag("Yuanti SC")
                            Text("Arial Rounded").tag("Arial Rounded")
                            Text("Helvetica Neue").tag("Helvetica Neue")
                        }
                        .labelsHidden()
                    }
                    HStack {
                        Text("歌词颜色")
                            .frame(width: 80, alignment: .leading)
                        NativeColorPopover(color: $settings.textColor, label: "歌词颜色")
                            .frame(width: 54, height: 28)
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    Button("恢复默认") {
                        settings.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 600)
    }

}

#Preview {
    ContentView()
}

// Host the native color panel's content in an anchored popover. The shared
// panel keeps ownership of its pickers; restore its content when dismissed.
private struct NativeColorPopover: NSViewRepresentable {
    @Binding var color: Color
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator,
                              action: #selector(Coordinator.toggle(_:)))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel(label)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.owner = self
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(color).cgColor
        button.layer?.cornerRadius = 6
        button.isBordered = false
        if context.coordinator.popover.isShown {
            let panel = NSColorPanel.shared
            if panel.color != NSColor(color) { panel.color = NSColor(color) }
        }
    }

    static func dismantleNSView(_ view: NSButton, coordinator: Coordinator) {
        coordinator.popover.close()
        coordinator.restorePanel()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        static weak var active: Coordinator?
        var owner: NativeColorPopover
        let popover = NSPopover()
        private var panelContent: NSView?
        private var presetView: NSView?
        private weak var favoritesView: NSView?
        private let presets: [NSColor] = [
            .white, .lightGray, .gray, .darkGray, .black,
            .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemMint,
            .systemTeal, .systemCyan, .systemBlue, .systemIndigo, .systemPurple,
            .systemPink, .brown, NSColor(srgbRed: 1, green: 0.7, blue: 0.8, alpha: 1),
            NSColor(srgbRed: 0.65, green: 0.8, blue: 1, alpha: 1),
            NSColor(srgbRed: 0.75, green: 0.65, blue: 0.95, alpha: 1)
        ]

        init(_ owner: NativeColorPopover) {
            self.owner = owner
            super.init()
            popover.behavior = .transient
            popover.delegate = self
        }

        @objc func toggle(_ sender: NSButton) {
            if popover.isShown { popover.performClose(sender); return }
            Self.active?.popover.close()
            let panel = NSColorPanel.shared
            panel.orderOut(nil)
            panel.showsAlpha = true
            panel.isContinuous = true
            panel.color = NSColor(owner.color)
            NotificationCenter.default.addObserver(
                self, selector: #selector(panelColorChanged(_:)),
                name: NSColorPanel.colorDidChangeNotification, object: panel
            )
            panel.setTarget(self)
            panel.setAction(#selector(colorChanged(_:)))
            guard let content = panel.contentView else { return }
            panelContent = content
            installPresets(in: content)
            let size = content.frame.size
            panel.contentView = NSView(frame: NSRect(origin: .zero, size: size))
            let controller = NSViewController()
            controller.view = content
            popover.contentViewController = controller
            popover.contentSize = size
            Self.active = self
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }

        private func installPresets(in content: NSView) {
            // AppKit exposes no public API for populating the favorites slots.
            // Replace only their presentation, leaving saved system favorites intact.
            func findFavorites(_ view: NSView) -> NSView? {
                if String(describing: type(of: view)) == "NSColorPanelFavoritesList" { return view }
                return view.subviews.lazy.compactMap { findFavorites($0) }.first
            }
            guard let favorites = findFavorites(content), let parent = favorites.superview else { return }
            let grid = NSStackView()
            grid.orientation = .vertical
            grid.alignment = .width
            grid.spacing = 2
            grid.distribution = .fillEqually
            for row in 0..<2 {
                let stack = NSStackView()
                stack.orientation = .horizontal
                stack.alignment = .height
                stack.spacing = 2
                stack.distribution = .fillEqually
                for column in 0..<10 {
                    let index = row * 10 + column
                    let button = NSButton(title: "", target: self, action: #selector(selectPreset(_:)))
                    button.tag = index
                    button.isBordered = false
                    button.wantsLayer = true
                    button.layer?.backgroundColor = presets[index].cgColor
                    button.layer?.cornerRadius = 2
                    button.layer?.borderWidth = 0.5
                    button.layer?.borderColor = NSColor.separatorColor.cgColor
                    button.setAccessibilityLabel("预设颜色 \(index + 1)")
                    stack.addArrangedSubview(button)
                    button.heightAnchor.constraint(equalTo: stack.heightAnchor).isActive = true
                }
                grid.addArrangedSubview(stack)
                stack.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
            }
            parent.addSubview(grid)
            grid.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                grid.leadingAnchor.constraint(equalTo: favorites.leadingAnchor, constant: 10),
                grid.trailingAnchor.constraint(equalTo: favorites.trailingAnchor, constant: -10),
                grid.centerYAnchor.constraint(equalTo: favorites.centerYAnchor),
                grid.heightAnchor.constraint(equalToConstant: 28)
            ])
            favorites.isHidden = true
            favoritesView = favorites
            presetView = grid
        }

        @objc private func selectPreset(_ sender: NSButton) {
            let panel = NSColorPanel.shared
            panel.color = presets[sender.tag].withAlphaComponent(panel.alpha)
            synchronizeColor(panel)
        }

        @objc private func colorChanged(_ sender: NSColorPanel) {
            synchronizeColor(sender)
        }

        @objc private func panelColorChanged(_ notification: Notification) {
            guard let panel = notification.object as? NSColorPanel else { return }
            synchronizeColor(panel)
        }

        private func synchronizeColor(_ panel: NSColorPanel) {
            guard let rgb = panel.color.usingColorSpace(.sRGB) else { return }
            let value = Color(.sRGB, red: rgb.redComponent, green: rgb.greenComponent,
                              blue: rgb.blueComponent, opacity: panel.alpha)
            if owner.color != value { owner.color = value }
        }

        func popoverDidClose(_ notification: Notification) { restorePanel() }

        func restorePanel() {
            NotificationCenter.default.removeObserver(
                self, name: NSColorPanel.colorDidChangeNotification, object: NSColorPanel.shared
            )
            guard let content = panelContent else { return }
            presetView?.removeFromSuperview()
            presetView = nil
            favoritesView?.isHidden = false
            favoritesView = nil
            content.removeFromSuperview()
            popover.contentViewController = nil
            let panel = NSColorPanel.shared
            panel.contentView = content
            panel.setTarget(nil)
            panel.setAction(nil)
            panel.orderOut(nil)
            panelContent = nil
            if Self.active === self { Self.active = nil }
        }
    }
}

// Native radio buttons retain keyboard focus and selection semantics.
private struct DisplayModePicker: NSViewRepresentable {
    @Binding var selection: LyricDisplayMode

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        for (index, title) in ["桌面展示歌词", "菜单栏展示歌词"].enumerated() {
            let button = NSButton(radioButtonWithTitle: title, target: context.coordinator,
                                  action: #selector(Coordinator.select(_:)))
            button.tag = index
            stack.addArrangedSubview(button)
        }
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        context.coordinator.owner = self
        for case let button as NSButton in stack.arrangedSubviews {
            button.state = (button.tag == 0 ? selection == .desktop : selection == .menuBar) ? .on : .off
        }
    }

    final class Coordinator: NSObject {
        var owner: DisplayModePicker
        init(_ owner: DisplayModePicker) { self.owner = owner }
        @objc func select(_ sender: NSButton) {
            owner.selection = sender.tag == 0 ? .desktop : .menuBar
        }
    }
}

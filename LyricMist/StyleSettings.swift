import SwiftUI

enum LyricDisplayMode: String, CaseIterable {
    case desktop
    case menuBar
}

class StyleSettings: ObservableObject {
    static let shared = StyleSettings()

    @Published var displayMode: LyricDisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "lyricDisplayMode") }
    }

    @Published var menuBarWidth: Double {
        didSet { UserDefaults.standard.set(menuBarWidth, forKey: "menuBarLyricWidth") }
    }

    static let desktopWidthRange: ClosedRange<Double> = 160...1600

    @Published var desktopWidth: Double {
        didSet { UserDefaults.standard.set(desktopWidth, forKey: "desktopLyricWidth") }
    }

    @Published var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "fontSize")
        }
    }

    @Published var fontName: String {
        didSet {
            UserDefaults.standard.set(fontName, forKey: "fontName")
        }
    }

    @Published var textColor: Color {
        didSet {
            saveColor(textColor, forKey: "textColor")
        }
    }

    @Published var highlightColor: Color {
        didSet {
            saveColor(highlightColor, forKey: "highlightColor")
        }
    }

    private init() {
        self.displayMode = LyricDisplayMode(rawValue: UserDefaults.standard.string(forKey: "lyricDisplayMode") ?? "") ?? .desktop
        let width = UserDefaults.standard.object(forKey: "menuBarLyricWidth") as? Double ?? 200
        self.menuBarWidth = width.isFinite ? min(300, max(100, width)) : 200
        let desktopWidth = UserDefaults.standard.object(forKey: "desktopLyricWidth") as? Double ?? 800
        self.desktopWidth = desktopWidth.isFinite
            ? min(Self.desktopWidthRange.upperBound, max(Self.desktopWidthRange.lowerBound, desktopWidth)) : 800
        self.fontSize = UserDefaults.standard.object(forKey: "fontSize") as? CGFloat ?? 22
        self.fontName = UserDefaults.standard.string(forKey: "fontName") ?? "System"
        self.textColor = Self.loadColor(forKey: "textColor") ?? .white
        self.highlightColor = Self.loadColor(forKey: "highlightColor") ?? Color(red: 0.22, green: 0.74, blue: 0.97)
    }

    func resetToDefaults() {
        displayMode = .desktop
        menuBarWidth = 200
        desktopWidth = 800
        fontSize = 22
        fontName = "System"
        textColor = .white
        highlightColor = Color(red: 0.22, green: 0.74, blue: 0.97)
    }

    private func saveColor(_ color: Color, forKey key: String) {
        if let rgb = NSColor(color).usingColorSpace(.sRGB) {
            let data: [CGFloat] = [
                rgb.redComponent,
                rgb.greenComponent,
                rgb.blueComponent,
                rgb.alphaComponent
            ]
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadColor(forKey key: String) -> Color? {
        guard let data = UserDefaults.standard.array(forKey: key) as? [CGFloat],
              data.count >= 3 else {
            return nil
        }

        return Color(
            red: data[0],
            green: data[1],
            blue: data[2],
            opacity: data.count > 3 ? data[3] : 1.0
        )
    }
}

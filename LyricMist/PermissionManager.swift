import Foundation
import AppKit

class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    func requestAutomationPermissions() {
        // 使用 osascript 命令行工具来触发权限对话框
        // 这种方式更可靠地触发系统权限请求

        requestSpotifyPermission()
        requestMusicPermission()
    }

    private func requestSpotifyPermission() {
        let script = """
        tell application "System Events"
            set spotifyRunning to exists (process "Spotify")
        end tell

        if spotifyRunning then
            tell application "Spotify"
                try
                    get name
                on error errMsg number errNum
                    return "Error: " & errNum
                end try
            end tell
        end if

        return "OK"
        """

        executeOsascript(script, appName: "Spotify")
    }

    private func requestMusicPermission() {
        let script = """
        tell application "System Events"
            set musicRunning to exists (process "Music")
        end tell

        if musicRunning then
            tell application "Music"
                try
                    get name
                on error errMsg number errNum
                    return "Error: " & errNum
                end try
            end tell
        end if

        return "OK"
        """

        executeOsascript(script, appName: "Music")
    }

    private func executeOsascript(_ script: String, appName: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("[\(appName)] osascript 输出: \(output)")
            }
        } catch {
            print("[\(appName)] osascript 执行失败: \(error)")
        }
    }

    func showPermissionInstructions() {
        let alert = NSAlert()
        alert.messageText = "需要自动化权限"
        alert.informativeText = """
        LyricMist 需要控制音乐播放器的权限。

        请按以下步骤操作：

        1. 打开「系统设置」
        2. 进入「隐私与安全性」→「自动化」
        3. 找到 LyricMist 并勾选：
           • Spotify
           • Music

        如果列表中没有 LyricMist，请：
        1. 完全退出应用
        2. 确保 Spotify 或 Music 正在运行
        3. 重新启动 LyricMist
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemPreferences()
        }
    }

    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

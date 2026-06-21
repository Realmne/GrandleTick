import AppKit

enum BrowserService {
    // 1. 获取浏览器当前的活动标签页 URL。
    // 使用 AppleScript 是目前 macOS 上获取沙盒外浏览器 URL 的最可靠方式。
    static func fetchActiveURL(for appName: String) -> String? {
        // 1. 根据浏览器名称生成对应的 AppleScript 脚本代码。
        let script: String
        if appName.contains("Safari") {
            script = "tell application \"Safari\" to return URL of front document"
        } else if appName.contains("Chrome") {
            script = "tell application \"Google Chrome\" to return URL of active tab of front window"
        } else if appName.contains("Edge") {
            script = "tell application \"Microsoft Edge\" to return URL of active tab of front window"
        } else {
            return nil
        }

        // 2. 实例化并执行 AppleScript，获取当前标签页的 URL 字符串。
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            return result.stringValue
        }
        return nil
    }

    // 2. 检查应用是否属于受支持的浏览器。
    static func isBrowserApp(bundleId: String) -> Bool {
        bundleId.contains("Safari") || bundleId.contains("Chrome") || bundleId.contains("Edge")
    }
}

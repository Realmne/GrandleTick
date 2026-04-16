import AppKit
import SwiftData

struct BrowserTitleData {
    let displayTitle: String
    let groupedTitle: String
}

@Observable
class ActivityTracker {
    var currentAppName: String = ""
    var currentWindowTitle: String = ""    // ⭐ 用于 UI 显示的实时标题
    var currentGroupedTitle: String = ""   // ⭐ 用于后台统计的聚合标题
    
    static var rawTitleToDataCache: [String: BrowserTitleData] = [:]
    static var bvidToMainTitleCache: [String: String] = [:]
    
    init() {
        _ = checkAccessibilityPermissions()
        track()
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.track()
        }
    }
    
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func getBrowserURL(appName: String) -> String? {
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
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            return result.stringValue
        }
        return nil
    }
    
    private func extractBilibiliID(from url: String) -> String? {
        let pattern = "(BV[a-zA-Z0-9]+|ep[0-9]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.utf16.count)) {
            let nsString = url as NSString
            return nsString.substring(with: match.range)
        }
        return nil
    }
    
    func track() {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else { return }
        if activeApp.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        
        if !AXIsProcessTrusted() {
            self.currentAppName = "权限受阻"
            self.currentWindowTitle = "需开启辅助功能权限"
            self.currentGroupedTitle = "需开启辅助功能权限"
            return
        }
        
        let appName = activeApp.localizedName ?? "未知应用"
        let bundleId = activeApp.bundleIdentifier ?? ""
        
        let isPreview = bundleId == "com.apple.Preview" || appName == "预览"
        let isBrowser = bundleId.contains("Safari") || bundleId.contains("Chrome") || bundleId.contains("Edge")
        
        if !isPreview && !isBrowser {
            self.currentAppName = ""
            self.currentWindowTitle = ""
            self.currentGroupedTitle = ""
            return
        }
        
        let pid = activeApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        if result == .success {
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
            
            if titleResult == .success {
                var title = titleRef as! String
                let rawTitle = title
                
                // --- 预览 App 逻辑 ---
                if isPreview {
                    let components = title.components(separatedBy: " - ")
                    if components.count > 1 {
                        if let last = components.last, last.contains("页") || last.contains("Page") {
                            title = Array(components.dropLast()).joined(separator: " - ")
                        }
                    }
                    if let range = title.range(of: ".pdf", options: [.backwards, .caseInsensitive]) {
                        title = String(title[..<range.upperBound])
                    }
                    self.currentAppName = appName
                    self.currentWindowTitle = title
                    self.currentGroupedTitle = title
                    return
                }
                
                // --- 浏览器逻辑 ---
                if isBrowser {
                    if let cached = ActivityTracker.rawTitleToDataCache[rawTitle] {
                        self.currentAppName = appName
                        self.currentWindowTitle = cached.displayTitle
                        self.currentGroupedTitle = cached.groupedTitle
                        return
                    }
                    
                    var displayTitle = "常规网页浏览"
                    var groupedTitle = "常规网页浏览"
                    
                    if let urlString = self.getBrowserURL(appName: appName),
                       let url = URL(string: urlString),
                       let host = url.host?.lowercased() {
                        
                        if host.contains("yuanbao.tencent.com") {
                            displayTitle = "腾讯元宝"
                            groupedTitle = "腾讯元宝"
                        } else if host.contains("doubao.com") {
                            displayTitle = "豆包 (Doubao)"
                            groupedTitle = "豆包 (Doubao)"
                        } else if host.contains("gemini.google.com") {
                            displayTitle = "Google Gemini"
                            groupedTitle = "Google Gemini"
                        } else if host.contains("chatgpt.com") || host.contains("openai.com") {
                            displayTitle = "ChatGPT"
                            groupedTitle = "ChatGPT"
                        } else if host.contains("deepseek.com") {
                            displayTitle = "DeepSeek"
                            groupedTitle = "DeepSeek"
                        } else if host.contains("claude.ai") {
                            displayTitle = "Claude"
                            groupedTitle = "Claude"
                        }
                        else if host.contains("bilibili.com") {
                            if let bvid = self.extractBilibiliID(from: urlString) {
                                // ⭐ 核心修复：放宽拦截条件，只要标题里“包含”无标题字样，全部视为加载中
                                if rawTitle.isEmpty || rawTitle.contains("无标题") || rawTitle.lowercased().contains("untitled") {
                                    displayTitle = "网页加载中..."
                                    groupedTitle = "网页加载中..."
                                } else {
                                    var cleanTitle = rawTitle
                                    let bComponents = rawTitle.components(separatedBy: "_")
                                    if bComponents.count > 1 {
                                        cleanTitle = bComponents[0] + " (Bilibili)"
                                    } else {
                                        let dashComponents = rawTitle.components(separatedBy: " - ")
                                        if let first = dashComponents.first {
                                            cleanTitle = first + " (Bilibili)"
                                        }
                                    }
                                    
                                    displayTitle = cleanTitle
                                    
                                    if let mainTitle = ActivityTracker.bvidToMainTitleCache[bvid] {
                                        groupedTitle = mainTitle
                                    } else {
                                        ActivityTracker.bvidToMainTitleCache[bvid] = cleanTitle
                                        groupedTitle = cleanTitle
                                    }
                                }
                            } else {
                                displayTitle = "常规网页浏览"
                                groupedTitle = "常规网页浏览"
                            }
                        }
                    }
                    else {
                        let lowerTitle = rawTitle.lowercased()
                        if lowerTitle.contains("元宝") || lowerTitle.contains("yuanbao") { displayTitle = "腾讯元宝"; groupedTitle = "腾讯元宝" }
                        else if lowerTitle.contains("千问") || lowerTitle.contains("qianwen") { displayTitle = "通义千问"; groupedTitle = "通义千问" }
                        else if lowerTitle.contains("豆包") || lowerTitle.contains("doubao") { displayTitle = "豆包 (Doubao)"; groupedTitle = "豆包 (Doubao)" }
                        else if lowerTitle.contains("gemini") { displayTitle = "Google Gemini"; groupedTitle = "Google Gemini" }
                        else if lowerTitle.contains("chatgpt") { displayTitle = "ChatGPT"; groupedTitle = "ChatGPT" }
                        else if lowerTitle.contains("deepseek") { displayTitle = "DeepSeek"; groupedTitle = "DeepSeek" }
                        else if lowerTitle.contains("claude") { displayTitle = "Claude"; groupedTitle = "Claude" }
                        else if lowerTitle.contains("哔哩哔哩") || lowerTitle.contains("bilibili") {
                            // ⭐ 核心修复：在降级防线里也加上对“无标题”的拦截
                            if lowerTitle.contains("无标题") || lowerTitle.contains("untitled") {
                                displayTitle = "网页加载中..."
                                groupedTitle = "网页加载中..."
                            } else {
                                let bComponents = rawTitle.components(separatedBy: "_")
                                if bComponents.count > 1 {
                                    displayTitle = bComponents[0] + " (Bilibili)"
                                    groupedTitle = displayTitle
                                } else {
                                    displayTitle = "常规网页浏览"
                                    groupedTitle = "常规网页浏览"
                                }
                            }
                        }
                    }
                    
                    ActivityTracker.rawTitleToDataCache[rawTitle] = BrowserTitleData(displayTitle: displayTitle, groupedTitle: groupedTitle)
                    
                    self.currentAppName = appName
                    self.currentWindowTitle = displayTitle
                    self.currentGroupedTitle = groupedTitle
                    return
                }
            }
        }
        self.currentAppName = ""
        self.currentWindowTitle = ""
        self.currentGroupedTitle = ""
    }
}

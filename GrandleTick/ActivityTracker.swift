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
    
    // ⭐ 新增：暴露给 UsageManager 记录到数据库的精细化字段
    var currentDomain: String? = nil
    var currentBvid: String? = nil
    var currentFullUrl: String? = nil
    
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
        // ⭐ 每次重新追踪前，先重置精细化字段，防止非浏览器应用残留上次的数据
        self.currentDomain = nil
        self.currentBvid = nil
        self.currentFullUrl = nil
        
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
        
        let appBundleName = activeApp.bundleURL?.deletingPathExtension().lastPathComponent ?? appName
        
        let isWhitelistedApp = WhitelistManager.shared.whitelistedApps.contains { whitelistedApp in
            let target = whitelistedApp.lowercased()
            return target == appName.lowercased() || target == appBundleName.lowercased()
        }
        
        if !isWhitelistedApp {
            self.currentAppName = ""
            self.currentWindowTitle = ""
            self.currentGroupedTitle = ""
            return
        }
        
        let isBrowser = bundleId.contains("Safari") || bundleId.contains("Chrome") || bundleId.contains("Edge")
        let isPreview = bundleId == "com.apple.Preview" || appName == "预览"
        
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
                    // 取出 URL 先进行保存
                    let urlString = self.getBrowserURL(appName: appName)
                    self.currentFullUrl = urlString
                    
                    if let cached = ActivityTracker.rawTitleToDataCache[rawTitle] {
                        self.currentAppName = appName
                        self.currentWindowTitle = cached.displayTitle
                        self.currentGroupedTitle = cached.groupedTitle
                        
                        // 从 URL 中补全 domain 和 bvid
                        if let urlStr = urlString, let url = URL(string: urlStr), let host = url.host?.lowercased() {
                            if let matchedDomain = WhitelistManager.shared.whitelistedDomains.first(where: { host.contains($0) }) {
                                self.currentDomain = matchedDomain
                                if matchedDomain == "bilibili.com" {
                                    self.currentBvid = self.extractBilibiliID(from: urlStr)
                                }
                            }
                        }
                        return
                    }
                    
                    var displayTitle = rawTitle
                    var groupedTitle = rawTitle
                    var matchedAnyDomain = false
                    
                    if let urlStr = urlString,
                       let url = URL(string: urlStr),
                       let host = url.host?.lowercased() {
                        
                        // ⭐ 判断域名是否在自定义域名白名单里
                        if let matchedDomain = WhitelistManager.shared.whitelistedDomains.first(where: { host.contains($0) }) {
                            matchedAnyDomain = true
                            self.currentDomain = matchedDomain // 保存独立域名
                            
                            if matchedDomain == "bilibili.com" {
                                if let bvid = self.extractBilibiliID(from: urlStr) {
                                    self.currentBvid = bvid // 保存BV号
                                    
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
                                    displayTitle = "Bilibili"
                                    groupedTitle = "Bilibili"
                                }
                            } else {
                                let domainLabel = matchedDomain.components(separatedBy: ".").first?.capitalized ?? matchedDomain
                                displayTitle = rawTitle.isEmpty ? "网页加载中..." : rawTitle
                                groupedTitle = domainLabel
                            }
                        }
                    } else {
                        // 降级防线：AppleScript 取不到 URL 时，尝试从标题匹配白名单域名
                        let lowerTitle = rawTitle.lowercased()
                        if lowerTitle.contains("无标题") || lowerTitle.contains("untitled") {
                            displayTitle = "网页加载中..."
                            groupedTitle = "网页加载中..."
                            matchedAnyDomain = true
                        } else {
                            for domain in WhitelistManager.shared.whitelistedDomains {
                                let keyword = domain.components(separatedBy: ".").first ?? domain
                                if lowerTitle.contains(keyword) || (keyword == "bilibili" && lowerTitle.contains("哔哩哔哩")) {
                                    displayTitle = rawTitle
                                    groupedTitle = keyword.capitalized
                                    matchedAnyDomain = true
                                    self.currentDomain = domain // 降级时尽量保存匹配到的 domain
                                    break
                                }
                            }
                        }
                    }
                    
                    // 拦截不在域名白名单的浏览器行为
                    if !matchedAnyDomain {
                        self.currentAppName = ""
                        self.currentWindowTitle = ""
                        self.currentGroupedTitle = ""
                        self.currentDomain = nil
                        self.currentBvid = nil
                        self.currentFullUrl = nil
                        return
                    }
                    
                    ActivityTracker.rawTitleToDataCache[rawTitle] = BrowserTitleData(displayTitle: displayTitle, groupedTitle: groupedTitle)
                    
                    self.currentAppName = appName
                    self.currentWindowTitle = displayTitle
                    self.currentGroupedTitle = groupedTitle
                    return
                }
                
                // --- 常规第三方 App 逻辑 ---
                self.currentAppName = appName
                self.currentWindowTitle = rawTitle
                self.currentGroupedTitle = appName
                return
            }
        }
        
        self.currentAppName = ""
        self.currentWindowTitle = ""
        self.currentGroupedTitle = ""
    }
}

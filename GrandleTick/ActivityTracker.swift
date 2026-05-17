import AppKit
import SwiftData

struct BrowserTitleData {
    let displayTitle: String
    let groupedTitle: String
}

@Observable
class ActivityTracker {
    var currentAppName: String = ""
    var currentWindowTitle: String = ""    // 用于界面展示的实时标题
    var currentGroupedTitle: String = ""   // 用于后台统计的聚合标题
    
    var currentDomain: String? = nil
    var currentBilibiliId: String? = nil
    var currentFullUrl: String? = nil
    
    static var titleCache: [String: BrowserTitleData] = [:]
    static var bilibiliIdToMainTitleCache: [String: String] = [:]
    
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
    
    private func getBrowserUrl(appName: String) -> String? {
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
    
    private func extractBilibiliIdentifier(from url: String) -> String? {
        let pattern = "(BV[a-zA-Z0-9]+|ep[0-9]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.utf16.count)) {
            let nsString = url as NSString
            return nsString.substring(with: match.range)
        }
        return nil
    }

    private func matchedWhitelistedDomainFromHost(_ host: String) -> String? {
        WhitelistManager.shared.whitelistedDomains.first { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }

    private func browserTitleCacheKey(originalTitle: String, domain: String?) -> String {
        "\(domain ?? "_no_domain_")|\(originalTitle)"
    }
    
    func track() {
        // 1. 每次重新追踪前，先重置浏览器精细化字段。
        //    这样可以避免从浏览器切到普通应用时，上一条域名和链接信息残留到本次记录。
        self.currentDomain = nil
        self.currentBilibiliId = nil
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
            let lowercasedWhitelistedApp = whitelistedApp.lowercased()
            return lowercasedWhitelistedApp == appName.lowercased() || lowercasedWhitelistedApp == appBundleName.lowercased()
        }
        
        if !isWhitelistedApp {
            self.currentAppName = ""
            self.currentWindowTitle = ""
            self.currentGroupedTitle = ""
            return
        }
        
        let isBrowserApp = bundleId.contains("Safari") || bundleId.contains("Chrome") || bundleId.contains("Edge")
        let isPreviewApp = bundleId == "com.apple.Preview" || appName == "预览"
        
        let processId = activeApp.processIdentifier
        let appRef = AXUIElementCreateApplication(processId)
        var windowRef: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        if focusedWindowResult == .success {
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
            
            if titleResult == .success {
                var title = titleRef as! String
                let rawTitle = title
                
                if isPreviewApp {
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
                
                // 2. 浏览器窗口优先根据当前网址识别真实域名。
                //    只有先拿到域名，后面的标题缓存和统计分组才不会把不同网站合并到一起。
                if isBrowserApp {
                    let browserUrl = self.getBrowserUrl(appName: appName)
                    self.currentFullUrl = browserUrl
                    let matchedWhitelistedDomain: String? = {
                        guard let browserUrl,
                              let url = URL(string: browserUrl),
                              let host = url.host?.lowercased() else {
                            return nil
                        }
                        return self.matchedWhitelistedDomainFromHost(host)
                    }()
                    
                    // 3. 标题缓存必须包含域名维度。
                    //    相同网页标题如果来自不同域名，必须命中不同缓存键，不能共用一条缓存结果。
                    if let cachedBrowserTitleData = ActivityTracker.titleCache[browserTitleCacheKey(originalTitle: rawTitle, domain: matchedWhitelistedDomain)] {
                        self.currentAppName = appName
                        self.currentWindowTitle = cachedBrowserTitleData.displayTitle
                        self.currentGroupedTitle = cachedBrowserTitleData.groupedTitle
                        
                        if let matchedDomain = matchedWhitelistedDomain {
                            self.currentDomain = matchedDomain
                            if matchedDomain == "bilibili.com", let currentBrowserUrl = browserUrl {
                                self.currentBilibiliId = self.extractBilibiliIdentifier(from: currentBrowserUrl)
                            }
                        }
                        return
                    }
                    
                    var displayTitle = rawTitle
                    var groupedTitle = rawTitle
                    var hasMatchedWhitelistedDomain = false
                    
                    // 4. 正常情况下直接依据网址做白名单匹配。
                    //    如果命中 Bilibili，则继续提取视频标识；否则按真实域名单独归类。
                    if let currentBrowserUrl = browserUrl,
                       let url = URL(string: currentBrowserUrl),
                       let host = url.host?.lowercased() {

                        if let matchedDomain = self.matchedWhitelistedDomainFromHost(host) {
                            hasMatchedWhitelistedDomain = true
                            self.currentDomain = matchedDomain
                            
                            if matchedDomain == "bilibili.com" {
                                if let bilibiliId = self.extractBilibiliIdentifier(from: currentBrowserUrl) {
                                    self.currentBilibiliId = bilibiliId
                                    
                                    if rawTitle.isEmpty || rawTitle.contains("无标题") || rawTitle.lowercased().contains("untitled") {
                                        displayTitle = "网页加载中..."
                                        groupedTitle = "网页加载中..."
                                    } else {
                                        var cleanedTitle = rawTitle
                                        let bilibiliTitleParts = rawTitle.components(separatedBy: "_")
                                        if bilibiliTitleParts.count > 1 {
                                            cleanedTitle = bilibiliTitleParts[0] + " (Bilibili)"
                                        } else {
                                            let dashSeparatedTitleParts = rawTitle.components(separatedBy: " - ")
                                            if let firstTitlePart = dashSeparatedTitleParts.first {
                                                cleanedTitle = firstTitlePart + " (Bilibili)"
                                            }
                                        }
                                        displayTitle = cleanedTitle
                                        if let mainTitle = ActivityTracker.bilibiliIdToMainTitleCache[bilibiliId] {
                                            groupedTitle = mainTitle
                                        } else {
                                            ActivityTracker.bilibiliIdToMainTitleCache[bilibiliId] = cleanedTitle
                                            groupedTitle = cleanedTitle
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
                        // 5. 如果浏览器没有返回网址，就退化成标题匹配。
                        //    这一步只作为兜底，尽量保留统计能力，但优先级低于真实网址匹配。
                        let lowercasedRawTitle = rawTitle.lowercased()
                        if lowercasedRawTitle.contains("无标题") || lowercasedRawTitle.contains("untitled") {
                            displayTitle = "网页加载中..."
                            groupedTitle = "网页加载中..."
                            hasMatchedWhitelistedDomain = true
                        } else {
                            for domain in WhitelistManager.shared.whitelistedDomains {
                                let keyword = domain.components(separatedBy: ".").first ?? domain
                                if lowercasedRawTitle.contains(keyword) || (keyword == "bilibili" && lowercasedRawTitle.contains("哔哩哔哩")) {
                                    displayTitle = rawTitle
                                    groupedTitle = keyword.capitalized
                                    hasMatchedWhitelistedDomain = true
                                    self.currentDomain = domain
                                    break
                                }
                            }
                        }
                    }
                    
                    // 6. 没有命中域名白名单的浏览器页面，直接忽略。
                    //    这样可以保证统计结果只保留用户允许追踪的网站。
                    if !hasMatchedWhitelistedDomain {
                        self.currentAppName = ""
                        self.currentWindowTitle = ""
                        self.currentGroupedTitle = ""
                        self.currentDomain = nil
                        self.currentBilibiliId = nil
                        self.currentFullUrl = nil
                        return
                    }
                    
                    ActivityTracker.titleCache[browserTitleCacheKey(originalTitle: rawTitle, domain: self.currentDomain)] = BrowserTitleData(displayTitle: displayTitle, groupedTitle: groupedTitle)
                    
                    self.currentAppName = appName
                    self.currentWindowTitle = displayTitle
                    self.currentGroupedTitle = groupedTitle
                    return
                }
                
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

import AppKit
import SwiftData
import CryptoKit

struct BrowserTitleData {
    let displayTitle: String
    let groupedTitle: String
}

@MainActor
@Observable
final class ActivityTracker {
    var currentAppName: String = ""
    var currentWindowTitle: String = ""
    var currentGroupedTitle: String = ""

    var currentDomain: String? = nil
    var currentBilibiliId: String? = nil
    var currentBilibiliTidV2: Int? = nil
    var currentFullUrl: String? = nil
    var currentPdfIdentifier: String? = nil
    var activityDidChange: (() -> Void)?

    static var titleCache: [String: BrowserTitleData] = [:]
    static var bilibiliIdToMainTitleCache: [String: String] = [:]
    private static var bilibiliMetadataCache: [String: BilibiliVideoMetadata] = [:]

    private var lastTrackAt: Date = .distantPast
    private var lastBrowserURLRefreshAt: Date = .distantPast
    private var lastTrustCheckAt: Date = .distantPast
    private var cachedAccessibilityTrusted = false
    private var lastResolvedSnapshot: TrackedSnapshot?
    private var pendingBrowserURLRefreshKeys: Set<BrowserURLRefreshKey> = []
    private var prefetchedBrowserURLResults: [BrowserURLRefreshKey: BrowserURLRefreshResult] = [:]
    private var pendingBilibiliMetadataRequests: Set<String> = []
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?
    private var observedProcessId: pid_t?
    nonisolated(unsafe) private var activeAppObserver: AXObserver?
    nonisolated(unsafe) private var observedFocusedWindow: AXUIElement?
    private var lastPublishedActivity: PublishedActivityState?

    init() {
        cachedAccessibilityTrusted = checkAccessibilityPermissions(prompt: true)
        track(forceRefresh: true)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // App 激活是系统能直接给到的最快信号；这里强制刷新，
                // 让上层 UsageManager 不必等下一次计时器 tick 才切换会话。
                self?.track(forceRefresh: true)
            }
        }
    }

    deinit {
        // 1. 移除系统前台应用切换通知观察者。
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        
        // 2. 释放 AXObserver 观察者，并从运行循环中移除关联的源，防止观察回调访问已被销毁的实例（野指针崩溃）。
        if let observer = activeAppObserver {
            if let window = observedFocusedWindow {
                AXObserverRemoveNotification(observer, window, kAXTitleChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func track(forceRefresh: Bool = false) {
        // 1. 先用轻量节流保护兜底轮询路径；事件触发会传 forceRefresh，不能被节流挡住。
        let now = Date()
        if !forceRefresh && now.timeIntervalSince(lastTrackAt) < AppConfig.trackInterval {
            return
        }
        lastTrackAt = now

        // 2. 辅助功能权限可能在系统设置里被用户改掉，事件驱动也需要定期重新确认。
        if now.timeIntervalSince(lastTrustCheckAt) >= AppConfig.trustRefreshInterval || forceRefresh {
            cachedAccessibilityTrusted = checkAccessibilityPermissions(prompt: false)
            lastTrustCheckAt = now
        }

        resetBrowserMetadata()

        // 3. 获取前台最上层应用，若获取不到或为当前 App，则清理状态。
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            removeActiveAppObserver()
            clearTrackedState()
            return
        }
        if activeApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            removeActiveAppObserver()
            clearTrackedState()
            return
        }

        // 4. 辅助功能权限受阻时，向界面更新状态，提示开启辅助功能权限。
        if !cachedAccessibilityTrusted {
            removeActiveAppObserver()
            currentAppName = "权限受阻"
            currentWindowTitle = "需开启辅助功能权限"
            currentGroupedTitle = "需开启辅助功能权限"
            publishActivityChangeIfNeeded()
            return
        }

        let appName = activeApp.localizedName ?? "未知应用"
        let bundleId = activeApp.bundleIdentifier ?? ""
        let processId = activeApp.processIdentifier

        // 5. 过滤掉不属于用户前台交互的应用（如系统服务、守护进程、屏保等）。
        guard isUserFacingApp(activeApp) else {
            removeActiveAppObserver()
            clearTrackedState()
            return
        }

        // 6. 对当前前台 App 安装 AXObserver，补齐 NSWorkspace 只通知“应用切换”、不通知“同一应用内切窗口/标题变化”的空白。
        installActiveAppObserverIfNeeded(processId: processId)

        let isBrowserApp = BrowserService.isBrowserApp(bundleId: bundleId)
        let isPreviewApp = bundleId == "com.apple.Preview" || appName == "预览"

        // 7. 获取当前焦点窗口及窗口标题。
        let appRef = AXUIElementCreateApplication(processId)
        var windowRef: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard focusedWindowResult == .success, let windowElement = windowRef else {
            observedFocusedWindow = nil
            clearTrackedState()
            return
        }
        observeTitleChangesIfNeeded(for: windowElement as! AXUIElement)

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
        guard titleResult == .success, let rawTitle = titleRef as? String else {
            clearTrackedState()
            return
        }

        if isPreviewApp {
            // 8. 针对预览 App：如果识别为 PDF 文档，则以 PDF 特殊路径进行匹配和上报；否则（如打开的是图片或处于空窗状态），则不拦截并落入后面的常规应用处理，记为娱乐/休闲时长。
            if let normalizedTitle = normalizedPreviewPDFTitle(from: rawTitle) {
                // (1) 复制焦点窗口的 AXDocument 属性获取真实的 file:// 协议路径
                var docRef: CFTypeRef?
                let docResult = AXUIElementCopyAttributeValue(windowElement as! AXUIElement, "AXDocument" as CFString, &docRef)
                let docUrl: URL? = {
                    if docResult == .success, let docUrlString = docRef as? String {
                        return URL(string: docUrlString)
                    }
                    return nil
                }()
                
                // (2) 使用系统 Inode 与快速文件哈希特征指纹唯一识别该 PDF
                let pdfId = generatePDFIdentifier(for: docUrl)

                applySnapshot(
                    TrackedSnapshot(
                        processId: processId,
                        appName: appName,
                        bundleId: bundleId,
                        rawTitle: rawTitle,
                        displayTitle: normalizedTitle,
                        groupedTitle: normalizedTitle,
                        domain: nil,
                        bilibiliIdentifier: nil,
                        bilibiliTidV2: nil,
                        fullUrl: nil,
                        pdfIdentifier: pdfId
                    )
                )
                return
            }
        }

        if isBrowserApp {
            resolveBrowserSnapshot(
                appName: appName,
                bundleId: bundleId,
                processId: processId,
                rawTitle: rawTitle,
                forceRefresh: forceRefresh,
                now: now
            )
            return
        }

        applySnapshot(
            TrackedSnapshot(
                processId: processId,
                appName: appName,
                bundleId: bundleId,
                rawTitle: rawTitle,
                displayTitle: rawTitle,
                groupedTitle: appName,
                domain: nil,
                bilibiliIdentifier: nil,
                bilibiliTidV2: nil,
                fullUrl: nil,
                pdfIdentifier: nil
            )
        )
    }

    private func resolveBrowserSnapshot(
        appName: String,
        bundleId: String,
        processId: pid_t,
        rawTitle: String,
        forceRefresh: Bool,
        now: Date
    ) {
        let refreshKey = BrowserURLRefreshKey(
            processId: processId,
            appName: appName,
            rawTitle: rawTitle
        )

        if let prefetchedResult = prefetchedBrowserURLResults.removeValue(forKey: refreshKey) {
            lastBrowserURLRefreshAt = now
            applyResolvedBrowserSnapshot(
                appName: appName,
                bundleId: bundleId,
                processId: processId,
                rawTitle: rawTitle,
                browserUrl: prefetchedResult.url
            )
            return
        }

        if let lastResolvedSnapshot,
           lastResolvedSnapshot.processId == processId,
           lastResolvedSnapshot.rawTitle == rawTitle,
           !forceRefresh {
            if now.timeIntervalSince(lastBrowserURLRefreshAt) < AppConfig.browserURLRefreshInterval {
                applySnapshot(lastResolvedSnapshot)
                return
            }

            scheduleBrowserURLRefresh(for: refreshKey)
            applySnapshot(lastResolvedSnapshot)
            return
        }

        let browserUrl = BrowserService.fetchActiveURL(for: appName)
        lastBrowserURLRefreshAt = now
        applyResolvedBrowserSnapshot(
            appName: appName,
            bundleId: bundleId,
            processId: processId,
            rawTitle: rawTitle,
            browserUrl: browserUrl
        )
    }

    private func applyResolvedBrowserSnapshot(
        appName: String,
        bundleId: String,
        processId: pid_t,
        rawTitle: String,
        browserUrl: String?
    ) {
        // 1. 从浏览器 URL 中提取域名，并进行白名单域名匹配。
        let matchedDomain: String? = {
            guard let browserUrl,
                  let url = URL(string: browserUrl),
                  let host = url.host?.lowercased() else {
                return nil
            }
            return matchedWhitelistedDomainFromHost(host) ?? host
        }()

        // 2. 如果是 Bilibili 网站，则分流到 Bilibili 的解析逻辑中。
        if matchedDomain == "bilibili.com",
           let browserUrl {
            resolveBilibiliSnapshot(
                appName: appName,
                bundleId: bundleId,
                processId: processId,
                rawTitle: rawTitle,
                browserUrl: browserUrl
            )
            return
        }

        // 3. 检查本地标题缓存以避免重复的字符串解析。
        if let cachedBrowserTitleData = ActivityTracker.titleCache[browserTitleCacheKey(originalTitle: rawTitle, domain: matchedDomain)] {
            let snapshot = TrackedSnapshot(
                processId: processId,
                appName: appName,
                bundleId: bundleId,
                rawTitle: rawTitle,
                displayTitle: cachedBrowserTitleData.displayTitle,
                groupedTitle: cachedBrowserTitleData.groupedTitle,
                domain: matchedDomain,
                bilibiliIdentifier: matchedDomain == "bilibili.com" ? browserUrl.flatMap(BilibiliService.extractIdentifier) : nil,
                bilibiliTidV2: nil,
                fullUrl: browserUrl,
                pdfIdentifier: nil
            )
            applySnapshot(snapshot)
            return
        }

        var displayTitle = rawTitle
        var groupedTitle = rawTitle
        var hasMatchedDomain = false
        var targetMatchedDomain: String? = matchedDomain
        var bilibiliIdentifier: String?

        if let currentBrowserUrl = browserUrl,
           let url = URL(string: currentBrowserUrl),
           let host = url.host?.lowercased() {
            hasMatchedDomain = true
            let resolvedDomain = matchedWhitelistedDomainFromHost(host) ?? host
            targetMatchedDomain = resolvedDomain

            if resolvedDomain == "bilibili.com" {
                bilibiliIdentifier = BilibiliService.extractIdentifier(from: currentBrowserUrl)
                if rawTitle.isEmpty || rawTitle.contains("无标题") || rawTitle.lowercased().contains("untitled") {
                    displayTitle = "网页加载中..."
                    groupedTitle = "网页加载中..."
                } else {
                    var cleanedTitle = rawTitle
                    let bilibiliTitleParts = rawTitle.components(separatedBy: "_")
                    if bilibiliTitleParts.count > 1 {
                        cleanedTitle = bilibiliTitleParts[0] + " (Bilibili)"
                    } else if let firstTitlePart = rawTitle.components(separatedBy: " - ").first {
                        cleanedTitle = firstTitlePart + " (Bilibili)"
                    }
                    displayTitle = cleanedTitle
                    if let bilibiliIdentifier,
                       let mainTitle = ActivityTracker.bilibiliIdToMainTitleCache[bilibiliIdentifier] {
                        groupedTitle = mainTitle
                    } else if let bilibiliIdentifier {
                        ActivityTracker.bilibiliIdToMainTitleCache[bilibiliIdentifier] = cleanedTitle
                        groupedTitle = cleanedTitle
                    } else {
                        groupedTitle = cleanedTitle
                    }
                }
            } else {
                let domainLabel = resolvedDomain.components(separatedBy: ".").first?.capitalized ?? resolvedDomain
                displayTitle = rawTitle.isEmpty ? "网页加载中..." : rawTitle
                groupedTitle = domainLabel
            }
        } else {
            let lowercasedRawTitle = rawTitle.lowercased()
            if lowercasedRawTitle.contains("无标题") || lowercasedRawTitle.contains("untitled") {
                displayTitle = "网页加载中..."
                groupedTitle = "网页加载中..."
                hasMatchedDomain = true
            } else {
                var found = false
                for domain in WhitelistManager.shared.whitelistedDomains {
                    let keyword = domain.components(separatedBy: ".").first ?? domain
                    if lowercasedRawTitle.contains(keyword) || (keyword == "bilibili" && lowercasedRawTitle.contains("哔哩哔哩")) {
                        displayTitle = rawTitle
                        groupedTitle = keyword.capitalized
                        targetMatchedDomain = domain
                        hasMatchedDomain = true
                        found = true
                        break
                    }
                }
                if !found {
                    displayTitle = rawTitle
                    groupedTitle = appName
                    targetMatchedDomain = nil
                    hasMatchedDomain = true
                }
            }
        }

        guard hasMatchedDomain else {
            clearTrackedState()
            return
        }

        ActivityTracker.titleCache[browserTitleCacheKey(originalTitle: rawTitle, domain: targetMatchedDomain)] = BrowserTitleData(
            displayTitle: displayTitle,
            groupedTitle: groupedTitle
        )

        applySnapshot(
            TrackedSnapshot(
                processId: processId,
                appName: appName,
                bundleId: bundleId,
                rawTitle: rawTitle,
                displayTitle: displayTitle,
                groupedTitle: groupedTitle,
                domain: targetMatchedDomain,
                bilibiliIdentifier: bilibiliIdentifier,
                bilibiliTidV2: nil,
                fullUrl: browserUrl,
                pdfIdentifier: nil
            )
        )
    }

    private func scheduleBrowserURLRefresh(for refreshKey: BrowserURLRefreshKey) {
        guard !pendingBrowserURLRefreshKeys.contains(refreshKey) else { return }
        pendingBrowserURLRefreshKeys.insert(refreshKey)

        Task.detached(priority: .utility) {
            let browserUrl = BrowserService.fetchActiveURL(for: refreshKey.appName)

            await MainActor.run { [weak self] in
                guard let self else { return }

                self.pendingBrowserURLRefreshKeys.remove(refreshKey)
                self.prefetchedBrowserURLResults[refreshKey] = BrowserURLRefreshResult(url: browserUrl)

                if let lastResolvedSnapshot = self.lastResolvedSnapshot,
                   lastResolvedSnapshot.processId == refreshKey.processId,
                   lastResolvedSnapshot.rawTitle == refreshKey.rawTitle {
                    self.track(forceRefresh: true)
                }
            }
        }
    }

    private func installActiveAppObserverIfNeeded(processId: pid_t) {
        guard observedProcessId != processId else { return }
        removeActiveAppObserver()

        var observer: AXObserver?
        let result = AXObserverCreate(processId, activityTrackerAXObserverCallback, &observer)
        guard result == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(processId)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // 只监听会影响“当前统计对象”的通知：
        // - 焦点窗口变化用于同一 App 内切文档/窗口；
        // - 主窗口变化覆盖部分 App 不触发 focusedWindowChanged 的情况。
        AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, context)
        AXObserverAddNotification(observer, appElement, kAXMainWindowChangedNotification as CFString, context)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observedProcessId = processId
        activeAppObserver = observer
    }

    private func observeTitleChangesIfNeeded(for windowElement: AXUIElement) {
        guard let activeAppObserver else { return }
        if let observedFocusedWindow,
           CFEqual(observedFocusedWindow, windowElement) {
            return
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let observedFocusedWindow {
            AXObserverRemoveNotification(activeAppObserver, observedFocusedWindow, kAXTitleChangedNotification as CFString)
        }

        // 窗口标题经常在页面加载、PDF 翻页或编辑器切文档后才稳定，
        // 监听标题变化可以把轮询延迟压到系统通知触发时。
        AXObserverAddNotification(activeAppObserver, windowElement, kAXTitleChangedNotification as CFString, context)
        observedFocusedWindow = windowElement
    }

    private func removeActiveAppObserver() {
        if let activeAppObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(activeAppObserver), .commonModes)
        }
        observedProcessId = nil
        activeAppObserver = nil
        observedFocusedWindow = nil
    }

    fileprivate func handleAccessibilityEvent() {
        track(forceRefresh: true)
    }

    private func resolveBilibiliSnapshot(
        appName: String,
        bundleId: String,
        processId: pid_t,
        rawTitle: String,
        browserUrl: String
    ) {
        guard let bilibiliIdentifier = BilibiliService.extractIdentifier(from: browserUrl),
              bilibiliIdentifier.hasPrefix("BV") else {
            clearTrackedState()
            return
        }

        if let metadata = ActivityTracker.bilibiliMetadataCache[bilibiliIdentifier] {
            applySnapshot(
                TrackedSnapshot(
                    processId: processId,
                    appName: appName,
                    bundleId: bundleId,
                    rawTitle: rawTitle,
                    displayTitle: metadata.title,
                    // 知识类视频保留具体标题并按 BV 号累计；
                    // 娱乐类统一折叠成“娱乐”，后续统计页默认不把它算进学习向指标。
                    groupedTitle: metadata.isKnowledge ? metadata.title : AppConfig.bilibiliEntertainmentTitle,
                    domain: "bilibili.com",
                    bilibiliIdentifier: metadata.isKnowledge ? bilibiliIdentifier : nil,
                    bilibiliTidV2: metadata.tidV2,
                    fullUrl: nil,
                    pdfIdentifier: nil
                )
            )
            return
        }

        fetchBilibiliMetadataIfNeeded(for: bilibiliIdentifier)
        clearTrackedState()
    }

    private func fetchBilibiliMetadataIfNeeded(for bilibiliIdentifier: String) {
        guard !pendingBilibiliMetadataRequests.contains(bilibiliIdentifier) else { return }
        pendingBilibiliMetadataRequests.insert(bilibiliIdentifier)

        Task { [weak self] in
            let metadata = await BilibiliService.fetchMetadata(for: bilibiliIdentifier)
            await MainActor.run {
                guard let self else { return }
                self.pendingBilibiliMetadataRequests.remove(bilibiliIdentifier)
                if let metadata {
                    ActivityTracker.bilibiliMetadataCache[bilibiliIdentifier] = metadata
                }
                self.track(forceRefresh: true)
            }
        }
    }

    private func normalizedPreviewPDFTitle(from title: String) -> String? {
        var cleanedTitle = title
        let components = cleanedTitle.components(separatedBy: " - ")
        if components.count > 1, let last = components.last, last.contains("页") || last.contains("Page") {
            cleanedTitle = Array(components.dropLast()).joined(separator: " - ")
        }
        guard let range = cleanedTitle.range(of: ".pdf", options: [.backwards, .caseInsensitive]) else {
            return nil
        }

        // 预览只在明确识别出 PDF 文件名时才参与统计，
        // 避免欢迎页、图片或其它非 PDF 文档被误算进学习时长。
        return String(cleanedTitle[..<range.upperBound])
    }

    private func matchedWhitelistedDomainFromHost(_ host: String) -> String? {
        WhitelistManager.shared.whitelistedDomains.first { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }

    /// 1. 判断是否属于正常的用户前台应用，过滤掉状态栏图标、后台常驻服务和系统级底层 UI。
    private func isUserFacingApp(_ activeApp: NSRunningApplication) -> Bool {
        // 1. 检查应用的激活策略：仅允许 regular（拥有常规 Dock 图标和主窗口）应用通过，
        // 从而直接把 accessory（仅状态栏图标的辅助软件）和 prohibited（后台服务）排除，防止系统后台进程干扰。
        guard activeApp.activationPolicy == .regular else {
            return false
        }

        // 2. 排除部分虽属于常规激活策略，但实为系统功能底座的内置 Bundle 标识。
        guard let bundleId = activeApp.bundleIdentifier else {
            return false
        }

        let excludedBundleIds: Set<String> = [
            "com.apple.finder",           // 访达（文件管理器）作为纯操作底座，不算做具体娱乐或学习时长
            "com.apple.dock",             // Dock 快捷栏
            "com.apple.loginwindow",      // 锁屏或登录窗口
            "com.apple.ScreenSaver.Engine", // 屏保程序
            "com.apple.controlcenter",    // 控制中心
            "com.apple.notificationcenterui", // 通知面板
            "com.apple.SystemUIServer",   // 系统菜单栏
            "com.apple.Siri",             // 语音助手界面
            "com.apple.accessibility.AccessibilityVisualsAgent", // 辅助功能弹窗
            "com.apple.Spotlight"         // Spotlight 聚焦搜索面板
        ]

        if excludedBundleIds.contains(bundleId) {
            return false
        }

        // 3. 根据 Bundle 所在的绝对路径剔除位于系统库文件、核心组件或守护进程目录下的进程。
        if let bundleURL = activeApp.bundleURL {
            let path = bundleURL.path
            let excludedPaths = [
                "/System/Library/CoreServices",
                "/System/Library/Frameworks",
                "/System/Library/PrivateFrameworks",
                "/usr/libexec"
            ]
            for excludedPath in excludedPaths {
                if path.hasPrefix(excludedPath) {
                    return false
                }
            }
        }

        return true
    }

    private func browserTitleCacheKey(originalTitle: String, domain: String?) -> String {
        "\(domain ?? "_no_domain_")|\(originalTitle)"
    }

    private func resetBrowserMetadata() {
        currentDomain = nil
        currentBilibiliId = nil
        currentBilibiliTidV2 = nil
        currentFullUrl = nil
        currentPdfIdentifier = nil
    }

    /// 3. 根据 PDF 文件 URL 计算一个唯一的 Inode 和快速内容哈希值特征指纹，确保文件重命名后依然能够合并统计
    private func generatePDFIdentifier(for url: URL?) -> String? {
        guard let url else { return nil }
        
        // 1. 获取文件 Inode 唯一标识符（同磁盘分区重命名时此标识符不变）
        var inodeString = ""
        if let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let fileID = values.fileResourceIdentifier {
            inodeString = "\(fileID)"
        }
        
        // 2. 计算快速内容指纹 (文件大小 + 头部 64KB 哈希 + 尾部 64KB 哈希，确保文件复制/跨设备传输后能正确辨识)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? UInt64,
              let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return inodeString.isEmpty ? nil : inodeString
        }
        
        defer { try? fileHandle.close() }
        
        let chunkSize = min(Int(fileSize), 64 * 1024)
        guard let firstChunk = try? fileHandle.read(upToCount: chunkSize) else {
            return inodeString.isEmpty ? nil : inodeString
        }
        let firstHash = SHA256.hash(data: firstChunk).description.prefix(12)
        
        if fileSize > UInt64(chunkSize) {
            try? fileHandle.seek(toOffset: fileSize - UInt64(chunkSize))
        } else {
            try? fileHandle.seek(toOffset: 0)
        }
        guard let lastChunk = try? fileHandle.read(upToCount: chunkSize) else {
            return inodeString.isEmpty ? nil : inodeString
        }
        let lastHash = SHA256.hash(data: lastChunk).description.prefix(12)
        
        return "pdf_\(fileSize)_\(firstHash)_\(lastHash)"
    }

    private func clearTrackedState() {
        currentAppName = ""
        currentWindowTitle = ""
        currentGroupedTitle = ""
        resetBrowserMetadata()
        lastResolvedSnapshot = nil
        publishActivityChangeIfNeeded()
    }

    private func applySnapshot(_ snapshot: TrackedSnapshot) {
        currentAppName = snapshot.appName
        currentWindowTitle = snapshot.displayTitle
        currentGroupedTitle = snapshot.groupedTitle
        currentDomain = snapshot.domain
        currentBilibiliId = snapshot.bilibiliIdentifier
        currentBilibiliTidV2 = snapshot.bilibiliTidV2
        currentFullUrl = snapshot.fullUrl
        currentPdfIdentifier = snapshot.pdfIdentifier
        lastResolvedSnapshot = snapshot
        publishActivityChangeIfNeeded()
    }

    private func publishActivityChangeIfNeeded() {
        let currentActivity = PublishedActivityState(
            appName: currentAppName,
            groupedTitle: currentGroupedTitle,
            domain: currentDomain,
            bilibiliIdentifier: currentBilibiliId,
            fullUrl: currentFullUrl,
            pdfIdentifier: currentPdfIdentifier
        )
        guard currentActivity != lastPublishedActivity else { return }
        lastPublishedActivity = currentActivity
        activityDidChange?()
    }
}

private let activityTrackerAXObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let tracker = Unmanaged<ActivityTracker>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        tracker.handleAccessibilityEvent()
    }
}

private struct TrackedSnapshot {
    let processId: pid_t
    let appName: String
    let bundleId: String
    let rawTitle: String
    let displayTitle: String
    let groupedTitle: String
    let domain: String?
    let bilibiliIdentifier: String?
    let bilibiliTidV2: Int?
    let fullUrl: String?
    let pdfIdentifier: String?
}

private struct BrowserURLRefreshKey: Hashable, Sendable {
    let processId: pid_t
    let appName: String
    let rawTitle: String
}

private struct BrowserURLRefreshResult: Sendable {
    let url: String?
}

private struct PublishedActivityState: Equatable {
    let appName: String
    let groupedTitle: String
    let domain: String?
    let bilibiliIdentifier: String?
    let fullUrl: String?
    let pdfIdentifier: String?
}

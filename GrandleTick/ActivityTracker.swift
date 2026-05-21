import AppKit
import SwiftData

struct BrowserTitleData {
    let displayTitle: String
    let groupedTitle: String
}

private let bilibiliKnowledgeTidV2s: Set<Int> = [1010, 2084, 2085, 2086, 2087, 2088, 2089, 2090, 2091, 2092, 2093, 2094, 2095]
private let bilibiliEntertainmentTitle = "娱乐"

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

    static var titleCache: [String: BrowserTitleData] = [:]
    static var bilibiliIdToMainTitleCache: [String: String] = [:]
    private static var bilibiliMetadataCache: [String: BilibiliVideoMetadata] = [:]

    private let trackInterval: TimeInterval = 2
    private let browserURLRefreshInterval: TimeInterval = 5
    private let trustRefreshInterval: TimeInterval = 15

    private var lastTrackAt: Date = .distantPast
    private var lastBrowserURLRefreshAt: Date = .distantPast
    private var lastTrustCheckAt: Date = .distantPast
    private var cachedAccessibilityTrusted = false
    private var lastResolvedSnapshot: TrackedSnapshot?
    private var pendingBilibiliMetadataRequests: Set<String> = []

    init() {
        cachedAccessibilityTrusted = checkAccessibilityPermissions(prompt: true)
        track(forceRefresh: true)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.track(forceRefresh: true)
            }
        }
    }

    func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func track(forceRefresh: Bool = false) {
        let now = Date()
        if !forceRefresh && now.timeIntervalSince(lastTrackAt) < trackInterval {
            return
        }
        lastTrackAt = now

        if now.timeIntervalSince(lastTrustCheckAt) >= trustRefreshInterval || forceRefresh {
            cachedAccessibilityTrusted = checkAccessibilityPermissions(prompt: false)
            lastTrustCheckAt = now
        }

        resetBrowserMetadata()

        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            clearTrackedState()
            return
        }
        if activeApp.bundleIdentifier == Bundle.main.bundleIdentifier { return }

        if !cachedAccessibilityTrusted {
            currentAppName = "权限受阻"
            currentWindowTitle = "需开启辅助功能权限"
            currentGroupedTitle = "需开启辅助功能权限"
            return
        }

        let appName = activeApp.localizedName ?? "未知应用"
        let bundleId = activeApp.bundleIdentifier ?? ""
        let processId = activeApp.processIdentifier
        let appBundleName = activeApp.bundleURL?.deletingPathExtension().lastPathComponent ?? appName

        let isWhitelistedApp = WhitelistManager.shared.whitelistedApps.contains { whitelistedApp in
            let lowercasedWhitelistedApp = whitelistedApp.lowercased()
            return lowercasedWhitelistedApp == appName.lowercased() || lowercasedWhitelistedApp == appBundleName.lowercased()
        }

        if !isWhitelistedApp {
            clearTrackedState()
            return
        }

        let isBrowserApp = bundleId.contains("Safari") || bundleId.contains("Chrome") || bundleId.contains("Edge")
        let isPreviewApp = bundleId == "com.apple.Preview" || appName == "预览"

        let appRef = AXUIElementCreateApplication(processId)
        var windowRef: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard focusedWindowResult == .success, let windowElement = windowRef else {
            clearTrackedState()
            return
        }

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
        guard titleResult == .success, let rawTitle = titleRef as? String else {
            clearTrackedState()
            return
        }

        if isPreviewApp {
            let normalizedTitle = normalizedPreviewTitle(from: rawTitle)
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
                    fullUrl: nil
                )
            )
            return
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
                fullUrl: nil
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
        if let lastResolvedSnapshot,
           lastResolvedSnapshot.processId == processId,
           lastResolvedSnapshot.rawTitle == rawTitle,
           !forceRefresh,
           now.timeIntervalSince(lastBrowserURLRefreshAt) < browserURLRefreshInterval {
            applySnapshot(lastResolvedSnapshot)
            return
        }

        let browserUrl = getBrowserUrl(appName: appName)
        lastBrowserURLRefreshAt = now
        let matchedWhitelistedDomain: String? = {
            guard let browserUrl,
                  let url = URL(string: browserUrl),
                  let host = url.host?.lowercased() else {
                return nil
            }
            return matchedWhitelistedDomainFromHost(host)
        }()

        if matchedWhitelistedDomain == "bilibili.com",
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

        if let cachedBrowserTitleData = ActivityTracker.titleCache[browserTitleCacheKey(originalTitle: rawTitle, domain: matchedWhitelistedDomain)] {
            let snapshot = TrackedSnapshot(
                processId: processId,
                appName: appName,
                bundleId: bundleId,
                rawTitle: rawTitle,
                displayTitle: cachedBrowserTitleData.displayTitle,
                groupedTitle: cachedBrowserTitleData.groupedTitle,
                domain: matchedWhitelistedDomain,
                bilibiliIdentifier: matchedWhitelistedDomain == "bilibili.com" ? browserUrl.flatMap(extractBilibiliIdentifier) : nil,
                bilibiliTidV2: nil,
                fullUrl: browserUrl
            )
            applySnapshot(snapshot)
            return
        }

        var displayTitle = rawTitle
        var groupedTitle = rawTitle
        var hasMatchedWhitelistedDomain = false
        var matchedDomain: String?
        var bilibiliIdentifier: String?

        if let currentBrowserUrl = browserUrl,
           let url = URL(string: currentBrowserUrl),
           let host = url.host?.lowercased(),
           let resolvedDomain = matchedWhitelistedDomainFromHost(host) {
            hasMatchedWhitelistedDomain = true
            matchedDomain = resolvedDomain

            if resolvedDomain == "bilibili.com" {
                bilibiliIdentifier = extractBilibiliIdentifier(from: currentBrowserUrl)
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
                hasMatchedWhitelistedDomain = true
            } else {
                for domain in WhitelistManager.shared.whitelistedDomains {
                    let keyword = domain.components(separatedBy: ".").first ?? domain
                    if lowercasedRawTitle.contains(keyword) || (keyword == "bilibili" && lowercasedRawTitle.contains("哔哩哔哩")) {
                        displayTitle = rawTitle
                        groupedTitle = keyword.capitalized
                        matchedDomain = domain
                        hasMatchedWhitelistedDomain = true
                        break
                    }
                }
            }
        }

        guard hasMatchedWhitelistedDomain else {
            clearTrackedState()
            return
        }

        ActivityTracker.titleCache[browserTitleCacheKey(originalTitle: rawTitle, domain: matchedDomain)] = BrowserTitleData(
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
                domain: matchedDomain,
                bilibiliIdentifier: bilibiliIdentifier,
                bilibiliTidV2: nil,
                fullUrl: browserUrl
            )
        )
    }

    private func resolveBilibiliSnapshot(
        appName: String,
        bundleId: String,
        processId: pid_t,
        rawTitle: String,
        browserUrl: String
    ) {
        guard let bilibiliIdentifier = extractBilibiliIdentifier(from: browserUrl),
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
                    groupedTitle: metadata.isKnowledge ? metadata.title : bilibiliEntertainmentTitle,
                    domain: "bilibili.com",
                    bilibiliIdentifier: metadata.isKnowledge ? bilibiliIdentifier : nil,
                    bilibiliTidV2: metadata.tidV2,
                    fullUrl: nil
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
            let metadata = await Self.fetchBilibiliMetadata(for: bilibiliIdentifier)
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

    nonisolated private static func fetchBilibiliMetadata(for bilibiliIdentifier: String) async -> BilibiliVideoMetadata? {
        guard let url = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bilibiliIdentifier)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(BilibiliViewResponse.self, from: data),
              response.code == 0,
              let responseData = response.data else {
            return nil
        }

        let tidV2 = responseData.tidV2 ?? responseData.tid
        let title = responseData.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        return BilibiliVideoMetadata(
            title: title,
            tidV2: tidV2,
            isKnowledge: bilibiliKnowledgeTidV2s.contains(tidV2)
        )
    }

    private func normalizedPreviewTitle(from title: String) -> String {
        var cleanedTitle = title
        let components = cleanedTitle.components(separatedBy: " - ")
        if components.count > 1, let last = components.last, last.contains("页") || last.contains("Page") {
            cleanedTitle = Array(components.dropLast()).joined(separator: " - ")
        }
        if let range = cleanedTitle.range(of: ".pdf", options: [.backwards, .caseInsensitive]) {
            cleanedTitle = String(cleanedTitle[..<range.upperBound])
        }
        return cleanedTitle
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

    private func resetBrowserMetadata() {
        currentDomain = nil
        currentBilibiliId = nil
        currentBilibiliTidV2 = nil
        currentFullUrl = nil
    }

    private func clearTrackedState() {
        currentAppName = ""
        currentWindowTitle = ""
        currentGroupedTitle = ""
        resetBrowserMetadata()
        lastResolvedSnapshot = nil
    }

    private func applySnapshot(_ snapshot: TrackedSnapshot) {
        currentAppName = snapshot.appName
        currentWindowTitle = snapshot.displayTitle
        currentGroupedTitle = snapshot.groupedTitle
        currentDomain = snapshot.domain
        currentBilibiliId = snapshot.bilibiliIdentifier
        currentBilibiliTidV2 = snapshot.bilibiliTidV2
        currentFullUrl = snapshot.fullUrl
        lastResolvedSnapshot = snapshot
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
}

private struct BilibiliVideoMetadata {
    let title: String
    let tidV2: Int
    let isKnowledge: Bool
}

private struct BilibiliViewResponse: Decodable {
    let code: Int
    let data: BilibiliViewData?
}

private struct BilibiliViewData: Decodable {
    let tid: Int
    let tidV2: Int?
    let title: String

    enum CodingKeys: String, CodingKey {
        case tid
        case tidV2 = "tid_v2"
        case title
    }
}

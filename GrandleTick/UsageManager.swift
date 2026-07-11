import SwiftUI
import SwiftData

@MainActor
@Observable
final class UsageManager {
    var tracker = ActivityTracker()

    var currentWindowTodayDuration: TimeInterval = 0
    private(set) var currentCategoryTodayDuration: TimeInterval = 0
    private(set) var currentContentHistoricalDuration: TimeInterval = 0
    var modelContext: ModelContext?
    var menuBarTitleDidChange: ((String) -> Void)?

    private var trackingTimer: Timer?
    private var currentSession: ActiveSession?
    private var currentPersistedLog: ActivityLog?
    private var currentBaselineTodayDuration: TimeInterval = 0
    private var currentBaselineHistoricalDuration: TimeInterval = 0
    
    // 今日累计的学习和娱乐时长基准（不包含当前正在进行的会话），用于在弹窗大字中展现今日分类总时长。
    private var todayBaselineStudyDuration: TimeInterval = 0
    private var todayBaselineEntertainmentDuration: TimeInterval = 0

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        tracker.activityDidChange = { [weak self] in
            self?.handleActivityChange(at: Date())
        }
        tracker.track(forceRefresh: true)
        startSessionIfNeeded(at: Date())
        startTracking()
        publishMenuBarTitle()
    }

    func startTracking() {
        trackingTimer?.invalidate()

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleTrackingTick(at: Date())
            }
        }
    }

    func flushPendingSession() {
        persistCurrentSession(forceSave: true, endDate: Date())
    }

    // 清空数据库后重新建立当前会话，避免下一次计时心跳把清空前的历史基准带回界面。
    func restartTrackingAfterHistoryDeletion(at restartDate: Date = Date()) {
        // 1. 丢弃指向已删除日志的会话状态和所有旧基准。
        clearSessionState()

        // 2. 立即清空三个展示口径，确保界面不会短暂残留旧数值。
        setDisplayedDurations(
            currentActivityToday: 0,
            categoryToday: 0,
            contentHistorical: 0
        )

        // 3. 强制刷新真实前台后再调和会话。确认框关闭时 tracker 可能仍缓存着此前的 PDF/视频，
        // 直接用缓存启动会把确认框停留期间重新写入刚清空的数据库。
        tracker.track(forceRefresh: true)
        reconcileTrackedActivity(at: restartDate)
    }

    // 1. 处理计时器心跳。
    // 每秒执行一次，用于刷新展示时长和定期同步到数据库。
    private func handleTrackingTick(at now: Date) {
        // 1. Timer 仍保留给秒级菜单栏显示，同时作为 AX/系统通知漏发时的兜底刷新。
        tracker.track()
        reconcileTrackedActivity(at: now)

        // 2. 当前没有可统计对象时只刷新菜单栏，避免把空窗口或未授权状态计入时长。
        guard currentSession != nil else {
            publishMenuBarTitle()
            return
        }

        // 3. 展示值由当前时刻减会话开始时刻派生出来，避免事件切换和 Timer tick 互相影响。
        updateDisplayedDurations(at: now)

        if persistedLogNeedsCreation {
            createPersistedLog(endDate: now)
        } else if shouldPersistSession(at: now) {
            persistCurrentSession(forceSave: false, endDate: now)
        }
    }

    // 2. 处理活动状态变更。
    // 当 AXObserver 检测到窗口或应用切换时触发，确保统计对象及时更新。
    private func handleActivityChange(at now: Date) {
        reconcileTrackedActivity(at: now)
        updateDisplayedDurations(at: now)
    }

    // 3. 调和当前追踪到的活动。
    // 判断是否需要结算旧会话并开启新会话。
    private func reconcileTrackedActivity(at now: Date) {
        let trackedActivity = TrackedActivity(from: tracker)

        // 1. 统计身份变化时立即收尾旧会话，并用事件发生时刻启动新会话。
        if trackedActivity?.identity != currentSession?.identity {
            persistCurrentSession(forceSave: true, endDate: now)
            clearSessionState()
            setDisplayedDurations(
                currentActivityToday: 0,
                categoryToday: 0,
                contentHistorical: 0
            )
            startSessionIfNeeded(at: now)
            return
        }

        guard let trackedActivity, let currentSession else { return }

        // 2. 普通网站可能在同一域名内切换页面，累计身份不变但 fullUrl 会更新；这里保留最新 URL 供落库排查，同时不拆分累计口径。
        if trackedActivity.fullUrl != currentSession.fullUrl
            || trackedActivity.bilibiliTidV2 != currentSession.bilibiliTidV2 {
            self.currentSession = ActiveSession(
                identity: currentSession.identity,
                startDate: currentSession.startDate,
                appName: trackedActivity.appName,
                groupedTitle: trackedActivity.groupedTitle,
                domain: trackedActivity.domain,
                bilibiliIdentifier: trackedActivity.bilibiliIdentifier,
                bilibiliTidV2: trackedActivity.bilibiliTidV2,
                fullUrl: trackedActivity.fullUrl,
                pdfIdentifier: trackedActivity.pdfIdentifier
            )
        }
    }

    private var persistedLogNeedsCreation: Bool {
        currentSession != nil && currentPersistedLog == nil
    }

    private func shouldPersistSession(at now: Date) -> Bool {
        guard let currentPersistedLog else { return false }
        return now.timeIntervalSince(currentPersistedLog.startTime) - currentPersistedLog.duration >= AppConfig.persistenceInterval
    }

    // 4. 开启新会话并加载基准时长。
    private func startSessionIfNeeded(at startDate: Date) {
        guard let trackedActivity = TrackedActivity(from: tracker) else {
            clearSessionState()
            setDisplayedDurations(
                currentActivityToday: 0,
                categoryToday: 0,
                contentHistorical: 0
            )
            return
        }

        currentSession = ActiveSession(
            identity: trackedActivity.identity,
            startDate: startDate,
            appName: trackedActivity.appName,
            groupedTitle: trackedActivity.groupedTitle,
            domain: trackedActivity.domain,
            bilibiliIdentifier: trackedActivity.bilibiliIdentifier,
            bilibiliTidV2: trackedActivity.bilibiliTidV2,
            fullUrl: trackedActivity.fullUrl,
            pdfIdentifier: trackedActivity.pdfIdentifier
        )
        currentPersistedLog = nil

        // 如果是 PDF 且存在唯一标识符，触发自愈式后台迁移标记，自动为没有指纹的历史记录补充指纹
        if let pdfId = trackedActivity.pdfIdentifier {
            tagLegacyLogsWithIdentifier(appName: trackedActivity.appName, windowTitle: trackedActivity.groupedTitle, pdfIdentifier: pdfId)
        }

        // 1. 加载当前具体活动的今日和历史基准，用于菜单栏展示。
        let baseline = loadBaselineDurations(for: trackedActivity.identity, now: startDate)
        currentBaselineTodayDuration = baseline.today
        currentBaselineHistoricalDuration = baseline.historical

        // 2. 加载今天整天已入库的学习与娱乐总时长，用作弹窗累计值的基座。
        let todayTotals = loadTodayTotalDurations(now: startDate)
        todayBaselineStudyDuration = todayTotals.study
        todayBaselineEntertainmentDuration = todayTotals.entertainment

        // 3. 触发第一次的显示值刷新。
        updateDisplayedDurations(at: startDate)
    }

    /// 标记未绑定唯一指纹的历史 PDF 日志，以便重命名后仍然可以从历史累加时长中检索出
    private func tagLegacyLogsWithIdentifier(appName: String, windowTitle: String, pdfIdentifier: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
            log.appName == appName && log.windowTitle == windowTitle && log.pdfIdentifier == nil
        })
        
        do {
            let legacyLogs = try context.fetch(descriptor)
            if !legacyLogs.isEmpty {
                for log in legacyLogs {
                    log.pdfIdentifier = pdfIdentifier
                }
                try context.save()
                print("ℹ️ [Database] 成功为 \(legacyLogs.count) 条历史 PDF 日志标记了唯一标识符。")
            }
        } catch {
            print("❌ [Database] 标记历史 PDF 日志失败: \(error.localizedDescription)")
        }
    }

    private func createPersistedLog(endDate: Date) {
        guard let context = modelContext, let currentSession else { return }

        let duration = currentSessionDuration(until: endDate)
        guard duration > 0 else { return }

        let log = ActivityLog(
            appName: currentSession.appName,
            windowTitle: currentSession.groupedTitle,
            startTime: currentSession.startDate,
            duration: duration,
            domain: currentSession.domain,
            bilibiliIdentifier: currentSession.bilibiliIdentifier,
            bilibiliTidV2: currentSession.bilibiliTidV2,
            fullUrl: currentSession.fullUrl,
            pdfIdentifier: currentSession.pdfIdentifier
        )
        context.insert(log)
        try? context.save()
        currentPersistedLog = log
    }

    private func persistCurrentSession(forceSave: Bool, endDate: Date) {
        guard let context = modelContext, let currentSession else { return }

        let finalDuration = max(0, endDate.timeIntervalSince(currentSession.startDate))
        guard finalDuration > 0 else {
            if let currentPersistedLog {
                context.delete(currentPersistedLog)
                try? context.save()
            }
            clearSessionState()
            return
        }

        if currentPersistedLog == nil {
            createPersistedLog(endDate: endDate)
        }

        guard let currentPersistedLog else { return }

        if forceSave || currentPersistedLog.duration != finalDuration {
            currentPersistedLog.duration = finalDuration
            currentPersistedLog.domain = currentSession.domain
            currentPersistedLog.bilibiliIdentifier = currentSession.bilibiliIdentifier
            currentPersistedLog.bilibiliTidV2 = currentSession.bilibiliTidV2
            currentPersistedLog.fullUrl = currentSession.fullUrl
            currentPersistedLog.pdfIdentifier = currentSession.pdfIdentifier
            try? context.save()
        }
    }

    private func clearSessionState() {
        currentSession = nil
        currentPersistedLog = nil
        currentBaselineTodayDuration = 0
        currentBaselineHistoricalDuration = 0
        todayBaselineStudyDuration = 0
        todayBaselineEntertainmentDuration = 0
    }

    private func currentSessionDuration(until date: Date) -> TimeInterval {
        guard let currentSession else { return 0 }
        return max(0, date.timeIntervalSince(currentSession.startDate))
    }

    private func updateDisplayedDurations(at date: Date) {
        let duration = currentSessionDuration(until: date)
        
        // 1. 当前活动在今日累计的总时长，主要供菜单栏展示。
        let currentActivityToday = currentBaselineTodayDuration + duration
        
        // 2. 弹窗大字展示的今日分类总时长。根据当前会话属于“学习”还是“娱乐”决定累加哪一项。
        let categoryToday: TimeInterval
        if isCurrentSessionStudy {
            categoryToday = todayBaselineStudyDuration + duration
        } else {
            categoryToday = todayBaselineEntertainmentDuration + duration
        }

        // 3. 当前 PDF 或知识视频使用“会话开始前的全历史基准 + 当前会话时长”，
        // 而不是每秒重新查询数据库，避免已定期落库的当前日志被重复累计。
        let contentHistorical = currentContentDurationLabel == nil
            ? 0
            : currentBaselineHistoricalDuration + duration
        
        setDisplayedDurations(
            currentActivityToday: currentActivityToday,
            categoryToday: categoryToday,
            contentHistorical: contentHistorical
        )
    }

    // 5. 从数据库加载基准时长，用于今日和历史统计显示。
    private func loadBaselineDurations(for identity: SessionIdentity, now: Date) -> DurationBaseline {
        guard let context = modelContext else { return .zero }

        let appName = identity.appName
        let groupedTitle = identity.groupedTitle
        
        let matchingLogs: [ActivityLog]
        if let pdfId = identity.pdfIdentifier, !pdfId.isEmpty {
            // 1. 现代 PDF 记录只按稳定文件指纹匹配，避免两个同名但内容不同的 PDF 串账；
            // 仅对没有指纹的旧记录保留“应用 + 标题”兜底。
            let identifiedDescriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
                log.pdfIdentifier == pdfId
            })
            let legacyDescriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
                log.pdfIdentifier == nil && log.appName == appName && log.windowTitle == groupedTitle
            })
            let identifiedLogs = (try? context.fetch(identifiedDescriptor)) ?? []
            let legacyLogs = (try? context.fetch(legacyDescriptor)) ?? []
            matchingLogs = identifiedLogs + legacyLogs
        } else if let bilibiliIdentifier = identity.bilibiliIdentifier, !bilibiliIdentifier.isEmpty {
            // 2. 知识视频直接按 BV 号汇总，使同一视频在不同浏览器中打开或标题变化后仍连续累计。
            let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
                log.bilibiliIdentifier == bilibiliIdentifier
            })
            matchingLogs = (try? context.fetch(descriptor)) ?? []
        } else {
            // 3. 没有内容级稳定标识的普通应用或网站沿用原有身份口径。
            let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
                log.appName == appName && log.windowTitle == groupedTitle
            })
            matchingLogs = ((try? context.fetch(descriptor)) ?? []).filter { log in
                log.domain == identity.domain && log.bilibiliIdentifier == identity.bilibiliIdentifier
            }
        }

        // 4. 同一批匹配日志同时生成今日基准和全历史基准；当前会话尚未创建日志，因此后续可安全叠加实时秒数。
        let startOfDay = Calendar.current.startOfDay(for: now)
        let today = matchingLogs
            .filter { $0.startTime >= startOfDay }
            .reduce(0) { $0 + $1.duration }
        let historical = matchingLogs.reduce(0) { $0 + $1.duration }
        return DurationBaseline(today: today, historical: historical)
    }

    private func setDisplayedDurations(
        currentActivityToday: TimeInterval,
        categoryToday: TimeInterval,
        contentHistorical: TimeInterval
    ) {
        currentWindowTodayDuration = currentActivityToday
        currentCategoryTodayDuration = categoryToday
        currentContentHistoricalDuration = contentHistorical
        publishMenuBarTitle()
    }

    private func publishMenuBarTitle() {
        menuBarTitleDidChange?(formattedMenuDuration)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return h > 0
            ? String(format: "%02d时%02d分%02d秒", h, m, s)
            : String(format: "%02d分%02d秒", m, s)
    }

    var formattedMenuDuration: String {
        formatTime(currentWindowTodayDuration)
    }

    // 弹窗大字展示今天在当前分类（学习/娱乐）下的所有活动累计。
    var formattedPopoverDuration: String {
        formatTime(currentCategoryTodayDuration)
    }

    var formattedCurrentContentDuration: String {
        formatTime(currentContentHistoricalDuration)
    }

    var currentContentDurationLabel: String? {
        guard let currentSession else { return nil }

        let lowercasedAppName = currentSession.appName.lowercased()
        let isPreview = lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview")
        if isPreview && currentSession.groupedTitle.lowercased().contains(".pdf") {
            return "当前内容累计"
        }

        // 娱乐视频当前不会保存 BV 号，否则现有分类逻辑会把它误判为学习；
        // 因此这里只为具备稳定 BV 标识的知识视频展示可精确汇总的时长。
        if currentSession.domain == "bilibili.com", currentSession.bilibiliIdentifier != nil {
            return "当前内容累计"
        }

        return nil
    }

    // MARK: - Classification Helpers

    // 1. 用于判定当前活跃的会话是否属于专注学习分类。
    // 这与 ContentView.isStudyActive 和 PreparedLog.isStudy 保持完全一致的底层分类口径。
    var isCurrentSessionStudy: Bool {
        guard let currentSession = currentSession else { return false }
        let appName = currentSession.appName
        let windowTitle = currentSession.groupedTitle
        let domain = currentSession.domain
        
        let lowercasedAppName = appName.lowercased()
        let isWebsite = lowercasedAppName.contains("safari") || lowercasedAppName.contains("chrome") || lowercasedAppName.contains("edge")
        
        // 1. 如果是浏览器，校验域名是否在白名单内，并对 B 站进行特殊指纹校验。
        if isWebsite {
            guard let domain = domain else { return false }
            let isWhitelistedDomain = WhitelistManager.shared.whitelistedDomains.contains { $0.lowercased() == domain.lowercased() }
            
            // B 站视频必须通过 API 确认为知识区得到的 identifier 作为唯一分类依据，避免 URL 兜底逻辑错误分类。
            if domain == "bilibili.com" {
                return currentSession.bilibiliIdentifier != nil
            }
            
            return isWhitelistedDomain
        } 
        
        // 2. 如果是 PDF 查看器，校验是否正在查看 PDF 文件。
        if lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview") {
            return windowTitle.lowercased().contains(".pdf")
        } 
        
        // 3. 其它本地应用匹配应用白名单。
        return WhitelistManager.shared.whitelistedApps.contains { app in
            let lowercasedApp = app.lowercased()
            return lowercasedApp == lowercasedAppName || lowercasedApp.contains(lowercasedAppName) || lowercasedAppName.contains(lowercasedApp)
        }
    }

    // 2. 用于评估数据库历史记录中的某条日志是否属于学习分类。
    // 在读取今天已落库的所有日志累加今日总时长时使用此方法。
    private func isStudyLog(_ log: ActivityLog, whitelist: WhitelistSnapshot) -> Bool {
        // 1. 过滤掉无意义的系统权限提示或未知/无效空日志。
        if log.windowTitle.contains("权限") || log.windowTitle.contains("未知") || log.appName.isEmpty {
            return false
        }
        
        let lowercasedAppName = log.appName.lowercased()
        let isWebsite = lowercasedAppName.contains("safari") || lowercasedAppName.contains("chrome") || lowercasedAppName.contains("edge")
        
        // 2. 浏览器日志需要对白名单和 B 站专属标识进行校验。
        if isWebsite {
            let resolvedDomain: String?
            if let domain = log.domain, !domain.isEmpty {
                resolvedDomain = domain
            } else {
                let lowercasedWindowTitle = log.windowTitle.lowercased()
                resolvedDomain = whitelist.domainKeywords.first { entry in
                    lowercasedWindowTitle.contains(entry.keyword) || (entry.keyword == "bilibili" && lowercasedWindowTitle.contains("哔哩哔哩"))
                }?.domain
            }
            
            guard let domain = resolvedDomain else { return false }
            let isWhitelistedDomain = whitelist.domains.contains { $0.lowercased() == domain.lowercased() }
            
            if domain == "bilibili.com" {
                return log.bilibiliIdentifier != nil
            }
            
            return isWhitelistedDomain
        } else if lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview") {
            // 3. PDF 校验。
            return log.windowTitle.lowercased().contains(".pdf")
        } else {
            // 4. 应用白名单校验。
            return whitelist.lowercasedApps.contains { app in
                app == lowercasedAppName || app.contains(lowercasedAppName) || lowercasedAppName.contains(app)
            }
        }
    }

    // 3. 从数据库加载今天所有已落库的学习和娱乐总时长。
    private func loadTodayTotalDurations(now: Date) -> (study: TimeInterval, entertainment: TimeInterval) {
        guard let context = modelContext else { return (0, 0) }
        
        // 1. 计算今日零点的时间戳，用作日志筛选的下限。
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        // 2. 从数据库获取今天零点以后的所有活动日志。
        let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
            log.startTime >= startOfDay
        })
        
        let todayLogs = (try? context.fetch(descriptor)) ?? []
        
        // 3. 构造白名单快照，确保对于大量日志分类时使用轻量的高速查找。
        let whitelistSnapshot = WhitelistSnapshot(whitelist: WhitelistManager.shared)
        
        var studyTotal: TimeInterval = 0
        var entertainmentTotal: TimeInterval = 0
        
        // 4. 遍历今天所有的日志并进行分类时长累加。
        for log in todayLogs {
            if isStudyLog(log, whitelist: whitelistSnapshot) {
                studyTotal += log.duration
            } else {
                entertainmentTotal += log.duration
            }
        }
        
        return (studyTotal, entertainmentTotal)
    }
}

private struct SessionIdentity: Hashable {
    let appName: String
    let groupedTitle: String
    let domain: String?
    let bilibiliIdentifier: String?
    let pdfIdentifier: String?
}

private struct TrackedActivity {
    let identity: SessionIdentity
    let appName: String
    let groupedTitle: String
    let domain: String?
    let bilibiliIdentifier: String?
    let bilibiliTidV2: Int?
    let fullUrl: String?
    let pdfIdentifier: String?

    @MainActor
    init?(from tracker: ActivityTracker) {
        guard !tracker.currentAppName.isEmpty, !tracker.currentAppName.contains("权限受阻") else {
            return nil
        }

        appName = tracker.currentAppName
        groupedTitle = tracker.currentGroupedTitle
        domain = tracker.currentDomain
        bilibiliIdentifier = tracker.currentBilibiliId
        bilibiliTidV2 = tracker.currentBilibiliTidV2
        fullUrl = tracker.currentDomain == "bilibili.com" ? nil : tracker.currentFullUrl
        pdfIdentifier = tracker.currentPdfIdentifier
        identity = SessionIdentity(
            appName: appName,
            groupedTitle: groupedTitle,
            domain: domain,
            bilibiliIdentifier: bilibiliIdentifier,
            pdfIdentifier: pdfIdentifier
        )
    }
}

private struct ActiveSession {
    let identity: SessionIdentity
    let startDate: Date
    let appName: String
    let groupedTitle: String
    let domain: String?
    let bilibiliIdentifier: String?
    let bilibiliTidV2: Int?
    let fullUrl: String?
    let pdfIdentifier: String?
}

private struct DurationBaseline {
    let today: TimeInterval
    let historical: TimeInterval

    static let zero = DurationBaseline(today: 0, historical: 0)
}

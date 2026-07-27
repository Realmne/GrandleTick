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

    private var displayTimer: Timer?
    private var activityTransitionTimer: Timer?
    private var pendingActivityTransition: PendingActivityTransition?
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
        startDisplayTimer()
        publishMenuBarTitle()
    }

    func startDisplayTimer() {
        displayTimer?.invalidate()

        let timer = Timer(timeInterval: AppConfig.displayRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleDisplayTick(at: Date())
            }
        }
        // 展示计时必须保持稳定的秒级跳动；仅保留很小的调度容差，并加入 common 模式，
        // 避免用户操作菜单或控件时运行循环模式切换导致界面漏掉某一秒。
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    func flushPendingSession() {
        persistCurrentSession(forceSave: true, endDate: Date())
    }

    // 清空数据库后重新建立当前会话，避免下一次计时心跳把清空前的历史基准带回界面。
    func restartTrackingAfterHistoryDeletion(at restartDate: Date = Date()) {
        // 1. 丢弃指向已删除日志的会话状态和所有旧基准。
        cancelPendingActivityTransition()
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

    // 1. 处理纯展示计时器。
    // 每秒只根据当前会话的两个时间戳派生展示值，不访问辅助功能，也不重新识别前台窗口。
    private func handleDisplayTick(at now: Date) {
        // 1. 防抖确认期间仍按候选窗口的历史基准刷新界面，让用户从切入窗口的第一帧就看到正确累计值。
        if currentSession == nil, pendingActivityTransition != nil {
            updatePendingDisplayedDurations(at: now)
            return
        }

        // 2. 当前没有可统计对象时只刷新菜单栏，避免把空窗口或未授权状态计入时长。
        guard currentSession != nil else {
            publishMenuBarTitle()
            return
        }

        // 3. 展示值由当前时刻减会话开始时刻派生出来，计时精度与 Timer 实际触发时刻无关。
        updateDisplayedDurations(at: now)

        // 4. 每分钟更新一次当前日志仅用于崩溃恢复；正常窗口切换仍由事件路径立即结算并保存。
        if persistedLogNeedsCreation {
            createPersistedLog(endDate: now)
        } else if shouldPersistSession(at: now) {
            persistCurrentSession(forceSave: false, endDate: now)
        }
    }

    // 2. 处理活动状态变更。
    // 每个系统事件都会进入这里；快速切窗通过候选会话过滤，而不是在事件入口直接丢弃。
    private func handleActivityChange(at now: Date) {
        let trackedActivity = TrackedActivity(from: tracker)

        // 1. 当前统计身份未变化时，只同步 URL 等元数据，不打断已经连续运行的会话。
        if trackedActivity?.identity == currentSession?.identity,
           let trackedActivity,
           let currentSession {
            self.currentSession = updatedSession(currentSession, with: trackedActivity)
            updateDisplayedDurations(at: now)
            return
        }

        // 2. 一旦离开旧窗口就立即按事件时间结算，绝不能让后续寻找窗口的时间继续算在旧窗口上。
        if currentSession != nil {
            persistCurrentSession(forceSave: true, endDate: now)
            clearSessionState()
        }

        // 3. 新窗口先进入候选状态，但立即加载它的展示基准；若用户继续快速切换，
        // 只替换候选且不创建数据库会话，同时界面也不会在防抖期间闪回 00分00秒。
        queuePendingActivityTransition(trackedActivity, observedAt: now)
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
        self.currentSession = updatedSession(currentSession, with: trackedActivity)
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

        startSession(for: trackedActivity, at: startDate)
    }

    private func startSession(for trackedActivity: TrackedActivity, at startDate: Date) {
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

    private func queuePendingActivityTransition(
        _ trackedActivity: TrackedActivity?,
        observedAt: Date
    ) {
        guard let trackedActivity else {
            cancelPendingActivityTransition()
            setDisplayedDurations(
                currentActivityToday: 0,
                categoryToday: 0,
                contentHistorical: 0
            )
            return
        }

        // 同一候选身份的异步元数据补全不算再次切窗：更新内容即可，保留最初切入该窗口的时间戳。
        if let pendingActivityTransition,
           pendingActivityTransition.activity.identity == trackedActivity.identity {
            self.pendingActivityTransition = PendingActivityTransition(
                activity: trackedActivity,
                observedAt: pendingActivityTransition.observedAt,
                baseline: pendingActivityTransition.baseline,
                todayStudyDuration: pendingActivityTransition.todayStudyDuration,
                todayEntertainmentDuration: pendingActivityTransition.todayEntertainmentDuration
            )
            updatePendingDisplayedDurations(at: observedAt)
            return
        }

        // 1. 候选阶段只读取展示基准，不建立正式会话或数据库记录；
        // 这样既保留快速切窗过滤策略，又能立即呈现新窗口已有的累计时长。
        let baseline = loadBaselineDurations(for: trackedActivity.identity, now: observedAt)
        let todayTotals = loadTodayTotalDurations(now: observedAt)

        activityTransitionTimer?.invalidate()
        pendingActivityTransition = PendingActivityTransition(
            activity: trackedActivity,
            observedAt: observedAt,
            baseline: baseline,
            todayStudyDuration: todayTotals.study,
            todayEntertainmentDuration: todayTotals.entertainment
        )
        updatePendingDisplayedDurations(at: observedAt)

        // 2. 只有候选窗口稳定超过防抖时间后才建立正式会话，避免为切换途中的窗口写入短记录。
        let timer = Timer(
            timeInterval: AppConfig.activityTransitionDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.commitPendingActivityTransition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        activityTransitionTimer = timer
    }

    private func commitPendingActivityTransition() {
        // 1. 取出最终候选，并确认当前窗口身份仍然一致，避免延迟回调启动已经被切走的窗口。
        guard let pendingActivityTransition else { return }
        activityTransitionTimer?.invalidate()
        activityTransitionTimer = nil
        self.pendingActivityTransition = nil

        guard currentSession == nil,
              TrackedActivity(from: tracker)?.identity == pendingActivityTransition.activity.identity else {
            return
        }

        // 2. 会话从最后一次真正切入该窗口的事件时间开始，而不是从防抖计时结束时开始，
        // 因此只过滤中间过渡窗口，不会少算最终稳定窗口的前两秒。
        startSession(
            for: pendingActivityTransition.activity,
            at: pendingActivityTransition.observedAt
        )
        updateDisplayedDurations(at: Date())
    }

    private func cancelPendingActivityTransition() {
        activityTransitionTimer?.invalidate()
        activityTransitionTimer = nil
        pendingActivityTransition = nil
    }

    private func updatedSession(
        _ currentSession: ActiveSession,
        with trackedActivity: TrackedActivity
    ) -> ActiveSession {
        ActiveSession(
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

    private func updatePendingDisplayedDurations(at date: Date) {
        guard let pendingActivityTransition else { return }

        // 1. 候选展示从真实切入时刻开始递增，防抖只延迟落库，不延迟用户看到计时。
        let duration = max(0, date.timeIntervalSince(pendingActivityTransition.observedAt))
        let currentActivityToday = pendingActivityTransition.baseline.today + duration

        // 2. 今日分类总时长按候选窗口的分类口径选择对应基准，避免先显示 0 再跳到历史累计值。
        let categoryToday = isStudyActivity(pendingActivityTransition.activity)
            ? pendingActivityTransition.todayStudyDuration + duration
            : pendingActivityTransition.todayEntertainmentDuration + duration

        // 3. PDF 和知识视频在候选阶段同样展示内容级历史累计，正式会话建立后数值可无缝衔接。
        let contentHistorical = contentDurationLabel(for: pendingActivityTransition.activity) == nil
            ? 0
            : pendingActivityTransition.baseline.historical + duration

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
        if let currentSession {
            return contentDurationLabel(
                appName: currentSession.appName,
                groupedTitle: currentSession.groupedTitle,
                domain: currentSession.domain,
                bilibiliIdentifier: currentSession.bilibiliIdentifier
            )
        }

        guard let pendingActivityTransition else { return nil }
        return contentDurationLabel(for: pendingActivityTransition.activity)
    }

    private func contentDurationLabel(for activity: TrackedActivity) -> String? {
        contentDurationLabel(
            appName: activity.appName,
            groupedTitle: activity.groupedTitle,
            domain: activity.domain,
            bilibiliIdentifier: activity.bilibiliIdentifier
        )
    }

    private func contentDurationLabel(
        appName: String,
        groupedTitle: String,
        domain: String?,
        bilibiliIdentifier: String?
    ) -> String? {
        let lowercasedAppName = appName.lowercased()
        let isPreview = lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview")
        if isPreview && groupedTitle.lowercased().contains(".pdf") {
            return "当前内容累计"
        }

        // 娱乐视频当前不会保存 BV 号，否则现有分类逻辑会把它误判为学习；
        // 因此这里只为具备稳定 BV 标识的知识视频展示可精确汇总的时长。
        if domain == "bilibili.com", bilibiliIdentifier != nil {
            return "当前内容累计"
        }

        return nil
    }

    // MARK: - Classification Helpers

    // 1. 用于判定当前活跃的会话是否属于专注学习分类。
    // 这与 ContentView.isStudyActive 和 PreparedLog.isStudy 保持完全一致的底层分类口径。
    var isCurrentSessionStudy: Bool {
        if let currentSession {
            return isStudyActivity(
                appName: currentSession.appName,
                windowTitle: currentSession.groupedTitle,
                domain: currentSession.domain,
                bilibiliIdentifier: currentSession.bilibiliIdentifier
            )
        }

        guard let pendingActivityTransition else { return false }
        return isStudyActivity(pendingActivityTransition.activity)
    }

    private func isStudyActivity(_ activity: TrackedActivity) -> Bool {
        isStudyActivity(
            appName: activity.appName,
            windowTitle: activity.groupedTitle,
            domain: activity.domain,
            bilibiliIdentifier: activity.bilibiliIdentifier
        )
    }

    private func isStudyActivity(
        appName: String,
        windowTitle: String,
        domain: String?,
        bilibiliIdentifier: String?
    ) -> Bool {
        
        let lowercasedAppName = appName.lowercased()
        let isWebsite = lowercasedAppName.contains("safari") || lowercasedAppName.contains("chrome") || lowercasedAppName.contains("edge")
        
        // 1. 如果是浏览器，校验域名是否在白名单内，并对 B 站进行特殊指纹校验。
        if isWebsite {
            guard let domain = domain else { return false }
            let isWhitelistedDomain = WhitelistManager.shared.whitelistedDomains.contains { $0.lowercased() == domain.lowercased() }
            
            // B 站视频必须通过 API 确认为知识区得到的 identifier 作为唯一分类依据，避免 URL 兜底逻辑错误分类。
            if domain == "bilibili.com" {
                return bilibiliIdentifier != nil
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
            let isWhitelistedDomain = whitelist.lowercasedDomainSet.contains(domain.lowercased())
            
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

private struct PendingActivityTransition {
    let activity: TrackedActivity
    let observedAt: Date
    let baseline: DurationBaseline
    let todayStudyDuration: TimeInterval
    let todayEntertainmentDuration: TimeInterval
}

private struct DurationBaseline {
    let today: TimeInterval
    let historical: TimeInterval

    static let zero = DurationBaseline(today: 0, historical: 0)
}

import SwiftUI
import SwiftData

@MainActor
@Observable
final class UsageManager {
    var tracker = ActivityTracker()

    var currentWindowTodayDuration: TimeInterval = 0
    var currentWindowHistoricalDuration: TimeInterval = 0
    var modelContext: ModelContext?
    var menuBarTitleDidChange: ((String) -> Void)?

    private var trackingTimer: Timer?
    private var currentSession: ActiveSession?
    private var currentPersistedLog: ActivityLog?
    private var currentBaselineTodayDuration: TimeInterval = 0
    private var currentBaselineHistoricalDuration: TimeInterval = 0

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        tracker.activityDidChange = { [weak self] in
            Task { @MainActor in
                self?.handleActivityChange(at: Date())
            }
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

    // 1. 处理计时器心跳。
    // 每秒执行一次，用于刷新展示时长和定期同步到数据库。
    private func handleTrackingTick(at now: Date) {
        // (1) Timer 仍保留给秒级菜单栏显示，同时作为 AX/系统通知漏发时的兜底刷新。
        tracker.track()
        reconcileTrackedActivity(at: now)

        // (2) 当前没有可统计对象时只刷新菜单栏，避免把空窗口或未授权状态计入时长。
        guard currentSession != nil else {
            publishMenuBarTitle()
            return
        }

        // (3) 展示值由当前时刻减会话开始时刻派生出来，避免事件切换和 Timer tick 互相影响。
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

        // (1) 统计身份变化时立即收尾旧会话，并用事件发生时刻启动新会话。
        if trackedActivity?.identity != currentSession?.identity {
            persistCurrentSession(forceSave: true, endDate: now)
            clearSessionState()
            setDisplayedDurations(today: 0, historical: 0)
            startSessionIfNeeded(at: now)
            return
        }

        guard let trackedActivity, let currentSession else { return }

        // (2) 普通网站可能在同一域名内切换页面，累计身份不变但 fullUrl 会更新；
        // 这里保留最新 URL 供落库排查，同时不拆分累计口径。
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
            setDisplayedDurations(today: 0, historical: 0)
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

        let baseline = loadBaselineDurations(for: trackedActivity.identity, now: startDate)
        currentBaselineTodayDuration = baseline.today
        currentBaselineHistoricalDuration = baseline.historical
        setDisplayedDurations(today: baseline.today, historical: baseline.historical)
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
    }

    private func currentSessionDuration(until date: Date) -> TimeInterval {
        guard let currentSession else { return 0 }
        return max(0, date.timeIntervalSince(currentSession.startDate))
    }

    private func updateDisplayedDurations(at date: Date) {
        let duration = currentSessionDuration(until: date)
        setDisplayedDurations(
            today: currentBaselineTodayDuration + duration,
            historical: currentBaselineHistoricalDuration + duration
        )
    }

    // 5. 从数据库加载基准时长，用于今日和历史统计显示。
    private func loadBaselineDurations(for identity: SessionIdentity, now: Date) -> DurationBaseline {
        guard let context = modelContext else { return .zero }

        let appName = identity.appName
        let groupedTitle = identity.groupedTitle
        
        let matchingLogs: [ActivityLog]
        if let pdfId = identity.pdfIdentifier, !pdfId.isEmpty {
            // 对 PDF 来说，基于 pdfIdentifier 或相同 windowTitle（传统记录）来匹配基准时长
            let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
                log.appName == appName && (log.pdfIdentifier == pdfId || log.windowTitle == groupedTitle)
            })
            matchingLogs = (try? context.fetch(descriptor)) ?? []
        } else {
            let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
                log.appName == appName && log.windowTitle == groupedTitle
            })
            matchingLogs = ((try? context.fetch(descriptor)) ?? []).filter { log in
                log.domain == identity.domain && log.bilibiliIdentifier == identity.bilibiliIdentifier
            }
        }

        let startOfDay = Calendar.current.startOfDay(for: now)
        let today = matchingLogs
            .filter { $0.startTime >= startOfDay }
            .reduce(0) { $0 + $1.duration }
        let historical = matchingLogs.reduce(0) { $0 + $1.duration }
        return DurationBaseline(today: today, historical: historical)
    }

    private func setDisplayedDurations(today: TimeInterval, historical: TimeInterval) {
        currentWindowTodayDuration = today
        currentWindowHistoricalDuration = historical
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

    var formattedPopoverDuration: String {
        formatTime(currentWindowHistoricalDuration)
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

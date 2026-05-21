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
    private var currentLiveDuration: TimeInterval = 0
    private var currentBaselineTodayDuration: TimeInterval = 0
    private var currentBaselineHistoricalDuration: TimeInterval = 0
    private var lastTickDate: Date?
    private let persistenceInterval: TimeInterval = 60

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        tracker.track(forceRefresh: true)
        startSessionIfNeeded(at: Date())
        startTracking()
        publishMenuBarTitle()
    }

    func startTracking() {
        trackingTimer?.invalidate()
        lastTickDate = Date()

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

    private func handleTrackingTick(at now: Date) {
        let delta = max(1, Int(round(now.timeIntervalSince(lastTickDate ?? now))))
        lastTickDate = now

        tracker.track()
        let trackedActivity = TrackedActivity(from: tracker)

        if trackedActivity?.identity != currentSession?.identity {
            persistCurrentSession(forceSave: true, endDate: now)
            clearSessionState()
            setDisplayedDurations(today: 0, historical: 0)
            startSessionIfNeeded(at: now)
        }

        guard currentSession != nil else {
            publishMenuBarTitle()
            return
        }

        currentLiveDuration += TimeInterval(delta)
        setDisplayedDurations(
            today: currentBaselineTodayDuration + currentLiveDuration,
            historical: currentBaselineHistoricalDuration + currentLiveDuration
        )

        if persistedLogNeedsCreation {
            createPersistedLog()
        } else if shouldPersistSession(at: now) {
            persistCurrentSession(forceSave: false, endDate: now)
        }
    }

    private var persistedLogNeedsCreation: Bool {
        currentSession != nil && currentPersistedLog == nil && currentLiveDuration > 0
    }

    private func shouldPersistSession(at now: Date) -> Bool {
        guard let currentPersistedLog else { return false }
        return now.timeIntervalSince(currentPersistedLog.startTime) - currentPersistedLog.duration >= persistenceInterval
    }

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
            fullUrl: trackedActivity.fullUrl
        )
        currentPersistedLog = nil
        currentLiveDuration = 0

        let baseline = loadBaselineDurations(for: trackedActivity.identity, now: startDate)
        currentBaselineTodayDuration = baseline.today
        currentBaselineHistoricalDuration = baseline.historical
        setDisplayedDurations(today: baseline.today, historical: baseline.historical)
    }

    private func createPersistedLog() {
        guard let context = modelContext, let currentSession else { return }

        let log = ActivityLog(
            appName: currentSession.appName,
            windowTitle: currentSession.groupedTitle,
            startTime: currentSession.startDate,
            duration: currentLiveDuration,
            domain: currentSession.domain,
            bilibiliIdentifier: currentSession.bilibiliIdentifier,
            bilibiliTidV2: currentSession.bilibiliTidV2,
            fullUrl: currentSession.fullUrl
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
            createPersistedLog()
        }

        guard let currentPersistedLog else { return }

        let roundedDuration = max(finalDuration, currentLiveDuration)
        if forceSave || currentPersistedLog.duration != roundedDuration {
            currentPersistedLog.duration = roundedDuration
            currentPersistedLog.domain = currentSession.domain
            currentPersistedLog.bilibiliIdentifier = currentSession.bilibiliIdentifier
            currentPersistedLog.bilibiliTidV2 = currentSession.bilibiliTidV2
            currentPersistedLog.fullUrl = currentSession.fullUrl
            try? context.save()
        }
    }

    private func clearSessionState() {
        currentSession = nil
        currentPersistedLog = nil
        currentLiveDuration = 0
        currentBaselineTodayDuration = 0
        currentBaselineHistoricalDuration = 0
    }

    private func loadBaselineDurations(for identity: SessionIdentity, now: Date) -> DurationBaseline {
        guard let context = modelContext else { return .zero }

        let appName = identity.appName
        let groupedTitle = identity.groupedTitle
        let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
            log.appName == appName && log.windowTitle == groupedTitle
        })

        let matchingLogs = ((try? context.fetch(descriptor)) ?? []).filter { log in
            let matchesFullURL = identity.fullUrl == nil || log.fullUrl == identity.fullUrl
            return log.domain == identity.domain
                && log.bilibiliIdentifier == identity.bilibiliIdentifier
                && matchesFullURL
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
    let fullUrl: String?
}

private struct TrackedActivity {
    let identity: SessionIdentity
    let appName: String
    let groupedTitle: String
    let domain: String?
    let bilibiliIdentifier: String?
    let bilibiliTidV2: Int?
    let fullUrl: String?

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
        let identityFullURL = tracker.currentDomain == "bilibili.com" ? nil : fullUrl
        identity = SessionIdentity(
            appName: appName,
            groupedTitle: groupedTitle,
            domain: domain,
            bilibiliIdentifier: bilibiliIdentifier,
            fullUrl: identityFullURL
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
}

private struct DurationBaseline {
    let today: TimeInterval
    let historical: TimeInterval

    static let zero = DurationBaseline(today: 0, historical: 0)
}

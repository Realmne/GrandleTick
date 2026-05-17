import SwiftUI
import SwiftData

@Observable
class UsageManager {
    var tracker = ActivityTracker()
    
    // 1. 菜单栏用：当前 PDF（窗口）的“今日”总时长
    var currentWindowTodayDuration: TimeInterval = 0
    
    // 2. 下拉面板用：当前 PDF（窗口）的“历史累计”总时长
    var currentWindowHistoricalDuration: TimeInterval = 0
    
    var modelContext: ModelContext?
    
    private var trackingTimer: Timer?
    private var uncommittedSeconds: TimeInterval = 0
    
    private var lastRecordedAppName: String = ""
    private var lastRecordedGroupedTitle: String = ""
    
    // 3. 缓存上一次任务的精细化数据。
    //    当窗口切换时，旧任务会先按这一组缓存值写入数据库，再切到新任务继续累计。
    private var lastRecordedDomain: String? = nil
    private var lastRecordedBilibiliId: String? = nil
    private var lastRecordedFullUrl: String? = nil
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        self.tracker.track()
        self.lastRecordedAppName = self.tracker.currentAppName
        self.lastRecordedGroupedTitle = self.tracker.currentGroupedTitle
        self.lastRecordedDomain = self.tracker.currentDomain
        self.lastRecordedBilibiliId = self.tracker.currentBilibiliId
        self.lastRecordedFullUrl = self.tracker.currentFullUrl
        self.updateDurations()
        startTracking()
    }
    
    func startTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.tracker.track()
            
            let currentAppName = self.tracker.currentAppName
            let currentGroupedTitle = self.tracker.currentGroupedTitle
            
            // 1. 只要应用名或聚合标题发生变化，就认为当前任务已经切换。
            // 2. 先把旧任务写入数据库，再把缓存切换到新任务，避免计时串到下一条记录。
            if currentAppName != self.lastRecordedAppName || currentGroupedTitle != self.lastRecordedGroupedTitle {
                self.saveCurrentActivity()
                self.lastRecordedAppName = currentAppName
                self.lastRecordedGroupedTitle = currentGroupedTitle
                
                self.lastRecordedDomain = self.tracker.currentDomain
                self.lastRecordedBilibiliId = self.tracker.currentBilibiliId
                self.lastRecordedFullUrl = self.tracker.currentFullUrl
                
                self.updateDurations()
            } else {
                // 3. 如果仍停留在同一条任务上，就继续累计未提交秒数。
                //    像 Bilibili 分集切换这种只改显示标题、不改聚合标题的情况，会在这里继续累加。
                if !currentAppName.isEmpty && !currentAppName.contains("权限受阻") {
                    self.uncommittedSeconds += 1
                    self.currentWindowTodayDuration += 1
                    self.currentWindowHistoricalDuration += 1
                    
                    if self.uncommittedSeconds >= 60 {
                        self.saveCurrentActivity()
                    }
                }
            }
        }
    }
    
    private func saveCurrentActivity() {
        guard let context = modelContext, uncommittedSeconds > 0 else { return }
        if lastRecordedAppName.isEmpty || lastRecordedAppName.contains("受阻") {
            uncommittedSeconds = 0
            return
        }
        
        // 1. 这里写入的是上一段已经结束的活动，不是当前刚采样到的新状态。
        // 2. 因此所有字段都必须来自 `lastRecorded...` 这一组缓存，不能直接读取实时追踪器。
        let log = ActivityLog(
            appName: lastRecordedAppName,
            windowTitle: lastRecordedGroupedTitle,
            startTime: Date().addingTimeInterval(-uncommittedSeconds),
            duration: uncommittedSeconds,
            domain: lastRecordedDomain,
            bilibiliIdentifier: lastRecordedBilibiliId,
            fullUrl: lastRecordedFullUrl
        )
        context.insert(log)
        try? context.save()
        uncommittedSeconds = 0
    }
    
    private func updateDurations() {
        guard let context = modelContext else { return }
        let currentAppName = tracker.currentAppName
        let currentGroupedTitle = tracker.currentGroupedTitle
        let startOfDay = Calendar.current.startOfDay(for: Date())
        
        // 1. 先计算当前任务在今天已经累计的时长。
        let todayDescriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
            log.startTime >= startOfDay
        })
        let todayLogs = (try? context.fetch(todayDescriptor)) ?? []
        let todayDurationFromDatabase = todayLogs.filter {
            $0.appName == currentAppName && $0.windowTitle == currentGroupedTitle
        }.reduce(0) { $0 + $1.duration }
        
        self.currentWindowTodayDuration = todayDurationFromDatabase + uncommittedSeconds
        
        // 2. 再计算当前任务在全部历史中的累计时长。
        let allLogsDescriptor = FetchDescriptor<ActivityLog>()
        let allLogs = (try? context.fetch(allLogsDescriptor)) ?? []
        let historicalDurationFromDatabase = allLogs.filter {
            $0.appName == currentAppName && $0.windowTitle == currentGroupedTitle
        }.reduce(0) { $0 + $1.duration }
        
        self.currentWindowHistoricalDuration = historicalDurationFromDatabase + uncommittedSeconds
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return h > 0 ? String(format: "%02d时%02d分%02d秒", h, m, s) : String(format: "%02d分%02d秒", m, s)
    }
    
    var formattedMenuDuration: String {
        formatTime(currentWindowTodayDuration)
    }
    
    var formattedPopoverDuration: String {
        formatTime(currentWindowHistoricalDuration)
    }
}

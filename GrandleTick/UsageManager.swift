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
    
    private var timer: Timer?
    private var uncommittedSeconds: TimeInterval = 0
    
    private var lastRecordedAppName: String = ""
    private var lastRecordedGroupedTitle: String = ""
    
    // ⭐ 新增：缓存上一次任务的精细化数据，以便在切换任务时一并存入数据库
    private var lastRecordedDomain: String? = nil
    private var lastRecordedBvid: String? = nil
    private var lastRecordedFullUrl: String? = nil
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        self.tracker.track()
        self.lastRecordedAppName = self.tracker.currentAppName
        self.lastRecordedGroupedTitle = self.tracker.currentGroupedTitle
        self.lastRecordedDomain = self.tracker.currentDomain
        self.lastRecordedBvid = self.tracker.currentBvid
        self.lastRecordedFullUrl = self.tracker.currentFullUrl
        self.updateDurations()
        startTracking()
    }
    
    func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.tracker.track()
            
            let currentApp = self.tracker.currentAppName
            let currentGrouped = self.tracker.currentGroupedTitle
            
            // 状态改变：如果聚合标题变了，才认为任务切换了
            if currentApp != self.lastRecordedAppName || currentGrouped != self.lastRecordedGroupedTitle {
                self.saveCurrentActivity()
                self.lastRecordedAppName = currentApp
                self.lastRecordedGroupedTitle = currentGrouped
                
                // ⭐ 同步更新精细化字段的缓存
                self.lastRecordedDomain = self.tracker.currentDomain
                self.lastRecordedBvid = self.tracker.currentBvid
                self.lastRecordedFullUrl = self.tracker.currentFullUrl
                
                self.updateDurations()
            } else {
                // 状态未变：比如切了分P，显示标题变了，但聚合标题没变，计时器继续累加
                if !currentApp.isEmpty && !currentApp.contains("权限受阻") {
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
        
        // ⭐ 写入数据库时，附加新增的独立字段
        let log = ActivityLog(
            appName: lastRecordedAppName,
            windowTitle: lastRecordedGroupedTitle,
            startTime: Date().addingTimeInterval(-uncommittedSeconds),
            duration: uncommittedSeconds,
            domain: lastRecordedDomain,
            bvid: lastRecordedBvid,
            fullUrl: lastRecordedFullUrl
        )
        context.insert(log)
        try? context.save()
        uncommittedSeconds = 0
    }
    
    private func updateDurations() {
        guard let context = modelContext else { return }
        let appName = tracker.currentAppName
        let groupedTitle = tracker.currentGroupedTitle
        let startOfDay = Calendar.current.startOfDay(for: Date())
        
        // --- 1. 计算【今日】时长 ---
        let todayDescriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
            log.startTime >= startOfDay
        })
        let todayLogs = (try? context.fetch(todayDescriptor)) ?? []
        let windowTodayDb = todayLogs.filter {
            $0.appName == appName && $0.windowTitle == groupedTitle
        }.reduce(0) { $0 + $1.duration }
        
        self.currentWindowTodayDuration = windowTodayDb + uncommittedSeconds
        
        // --- 2. 计算【历史累计】时长 ---
        let allDescriptor = FetchDescriptor<ActivityLog>()
        let allLogs = (try? context.fetch(allDescriptor)) ?? []
        let windowHistoricalDb = allLogs.filter {
            $0.appName == appName && $0.windowTitle == groupedTitle
        }.reduce(0) { $0 + $1.duration }
        
        self.currentWindowHistoricalDuration = windowHistoricalDb + uncommittedSeconds
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

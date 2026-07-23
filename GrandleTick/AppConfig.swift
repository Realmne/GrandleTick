import Foundation

enum AppConfig {
    // MARK: - Persistence
    static let persistenceInterval: TimeInterval = 60
    // 可见时长每秒自然跳动；窗口识别完全由系统事件驱动，不会随展示刷新重复执行。
    static let displayRefreshInterval: TimeInterval = 1
    // 快速切窗期间只保留最终稳定窗口，避免把寻找目标窗口的短暂停留计入统计。
    static let activityTransitionDebounceInterval: TimeInterval = 2
    static let browserURLRefreshInterval: TimeInterval = 15
    static let trustRefreshInterval: TimeInterval = 60

    // MARK: - Bilibili
    static let bilibiliKnowledgeTidV2s: Set<Int> = [1010, 2084, 2085, 2086, 2087, 2088, 2089, 2090, 2091, 2092, 2093, 2094, 2095]
    static let bilibiliEntertainmentTitle = "娱乐"
    static let bilibiliAPIUrl = "https://api.bilibili.com/x/web-interface/view?bvid="

    // MARK: - UI Defaults
    static let popoverWidth: CGFloat = 320
    static let popoverHeight: CGFloat = 700
    static let statisticsWidth: CGFloat = 860
    static let statisticsHeight: CGFloat = 680
    static let breakReminderWidth: CGFloat = 360
    static let breakReminderHeight: CGFloat = 142
    static let breakReminderScreenMargin: CGFloat = 18
}

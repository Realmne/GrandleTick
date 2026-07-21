import Foundation

enum AppConfig {
    // MARK: - Persistence
    static let persistenceInterval: TimeInterval = 60
    static let trackingHeartbeatInterval: TimeInterval = 2
    static let trackInterval: TimeInterval = 4
    static let browserURLRefreshInterval: TimeInterval = 15
    static let trustRefreshInterval: TimeInterval = 60

    // MARK: - Bilibili
    static let bilibiliKnowledgeTidV2s: Set<Int> = [1010, 2084, 2085, 2086, 2087, 2088, 2089, 2090, 2091, 2092, 2093, 2094, 2095]
    static let bilibiliEntertainmentTitle = "娱乐"
    static let bilibiliAPIUrl = "https://api.bilibili.com/x/web-interface/view?bvid="

    // MARK: - UI Defaults
    static let popoverWidth: CGFloat = 320
    static let popoverHeight: CGFloat = 570
    static let statisticsWidth: CGFloat = 860
    static let statisticsHeight: CGFloat = 680
}

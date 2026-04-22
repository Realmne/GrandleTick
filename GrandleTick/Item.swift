import Foundation
import SwiftData

@Model
final class ActivityLog {
    var appName: String      // 应用名，如“预览”
    var windowTitle: String  // 窗口标题，如“量子力学.pdf”
    var startTime: Date
    var duration: TimeInterval // 使用时长（秒）
    
    // ⭐ 新增的精细化统计字段
    var domain: String?      // 真实域名，例如 "bilibili.com"
    var bvid: String?        // B站专属标识，例如 "BV1xx..."
    var fullUrl: String?     // 完整的 URL
    
    init(appName: String, windowTitle: String, startTime: Date, duration: TimeInterval = 0, domain: String? = nil, bvid: String? = nil, fullUrl: String? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.startTime = startTime
        self.duration = duration
        self.domain = domain
        self.bvid = bvid
        self.fullUrl = fullUrl
    }
}

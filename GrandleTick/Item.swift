import Foundation
import SwiftData

@Model
final class ActivityLog {
    var appName: String              // 应用名，如“预览”
    var windowTitle: String          // 窗口标题，如“量子力学.pdf”
    var startTime: Date
    var duration: TimeInterval       // 使用时长（秒）
    
    var domain: String?                      // 真实域名，例如 "bilibili.com"
    @Attribute(originalName: "bvid")
    var bilibiliIdentifier: String?          // B站专属标识，例如 "BV1xx..."
    @Attribute(originalName: "fullUrl")
    var fullUrl: String?                     // 完整网页地址
    
    init(appName: String, windowTitle: String, startTime: Date, duration: TimeInterval = 0, domain: String? = nil, bilibiliIdentifier: String? = nil, fullUrl: String? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.startTime = startTime
        self.duration = duration
        self.domain = domain
        self.bilibiliIdentifier = bilibiliIdentifier
        self.fullUrl = fullUrl
    }
}

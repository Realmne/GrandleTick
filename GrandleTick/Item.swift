import Foundation
import SwiftData

@Model
final class ActivityLog {
    var appName: String      // 应用名，如“预览”
    var windowTitle: String  // 窗口标题，如“量子力学.pdf”
    var startTime: Date
    var duration: TimeInterval // 使用时长（秒）
    
    init(appName: String, windowTitle: String, startTime: Date, duration: TimeInterval = 0) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.startTime = startTime
        self.duration = duration
    }
}

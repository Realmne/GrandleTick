import SwiftUI
import SwiftData
import Foundation // 需引入 Foundation 处理文件目录

@main
struct GrandleTickApp: App {
    let container: ModelContainer
    @State private var usageManager: UsageManager

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)

        do {
            // 1. 获取当前系统用户的 Application Support 文件夹路径
            let applicationSupportDirectoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            
            // 2. 为当前应用创建一个专属的文件夹，避免与其他应用冲突
            let applicationDirectoryURL = applicationSupportDirectoryURL.appendingPathComponent("GrandleTick", isDirectory: true)
            
            // 3. 检查该文件夹是否存在，若不存在则创建
            if !FileManager.default.fileExists(atPath: applicationDirectoryURL.path) {
                try FileManager.default.createDirectory(at: applicationDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            // 4. 明确指定数据库文件（ActivityData.sqlite）的绝对路径
            let databaseFileURL = applicationDirectoryURL.appendingPathComponent("ActivityData.sqlite")
            
            // 5. 传入绝对路径，创建持久化的 ModelConfiguration
            let configuration = ModelConfiguration(url: databaseFileURL)
            
            // 6. 使用新的 configuration 实例化 ModelContainer
            container = try ModelContainer(for: ActivityLog.self, configurations: configuration)
            
            let context = container.mainContext
            _usageManager = State(initialValue: UsageManager(modelContext: context))
        } catch {
            fatalError("无法初始化数据库容器: \(error)")
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(usageManager: usageManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                Text(usageManager.formattedMenuDuration)
                    .monospacedDigit()
                
                if !usageManager.tracker.currentAppName.isEmpty {
                    Text("|")
                        .foregroundColor(.secondary)
                    Text(usageManager.tracker.currentAppName)
                        .font(.system(size: 12))
                }
            }
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)
    }
}

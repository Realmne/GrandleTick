import SwiftUI
import SwiftData

@main
struct GrandleTickApp: App {
    let container: ModelContainer
    @State private var usageManager: UsageManager

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)

        do {
            container = try ModelContainer(for: ActivityLog.self)
            let context = container.mainContext
            _usageManager = State(initialValue: UsageManager(modelContext: context))
        } catch {
            fatalError("无法初始化数据库容器: \(error)")
        }
    }
    
    var body: some Scene {
        // 在 GrandleTick__App.swift 的 body 中修改 MenuBarExtra 内部的 Text 绑定：

        MenuBarExtra {
                    ContentView(usageManager: usageManager)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                        // ⭐ 修改这里：绑定 PDF/当前窗口 今日时长
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

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    var usageManager: UsageManager
    
    static var statsWindow: NSWindow?
    static var whitelistWindow: NSWindow?
    
    private let requiredConfirmText = "我已知晓"
    
    var body: some View {
        VStack(spacing: 15) {
            if usageManager.tracker.currentWindowTitle == "需开启辅助功能权限" {
                Button(action: {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }) {
                    HStack {
                        Image(systemName: "exclamationmark.shield.fill")
                        Text("点击去开启辅助功能权限")
                            .font(.caption).bold()
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .center, spacing: 8) {
                let isUntracked = usageManager.tracker.currentAppName.isEmpty
                Text(isUntracked ? "已暂停统计" : "正在使用")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: isUntracked ? "pause.circle.fill" : "app.badge.checkmark.fill")
                        .foregroundColor(isUntracked ? .gray : .blue)
                    Text(isUntracked ? "未追踪的窗口" : usageManager.tracker.currentWindowTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Text(isUntracked ? "其他应用 (非白名单)" : usageManager.tracker.currentAppName)
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
            Divider()
            
            VStack(spacing: 5) {
                let isUntracked = usageManager.tracker.currentAppName.isEmpty
                let displayName = isUntracked ? "其他应用" : usageManager.tracker.currentWindowTitle
                
                Text(isUntracked ? "⏳ 已暂停记录" : "⏳ [\(displayName)] 合集总时长")
                    .font(.caption)
                    .bold()
                    .foregroundColor(isUntracked ? .gray : .blue)
                    .lineLimit(1)
                
                Text(usageManager.formattedPopoverDuration)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(isUntracked ? .gray : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: 50)
            }
            
            VStack(spacing: 10) {
                Button(action: openWhitelistWindow) {
                    HStack {
                        Image(systemName: "checklist")
                        Text("自定义白名单管理")
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Button(action: openStatisticsWindow) {
                    HStack {
                        Image(systemName: "chart.pie.fill")
                        Text("查看今日统计图表")
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Button(action: { showResetConfirmation() }) {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("清空所有历史数据")
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.8))
                
                Divider().padding(.horizontal, 40)
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                        Text("退出 GrandleTick")
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }
    
    func openWhitelistWindow() {
        if let existingWindow = ContentView.whitelistWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 550),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "白名单与追踪管理"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: WhitelistView())
        
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak window] _ in
            window?.close()
        }
        
        ContentView.whitelistWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openStatisticsWindow() {
        if let existingWindow = ContentView.statsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let statsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        statsWindow.title = "GrandleTick 历史记录"
        statsWindow.center()
        statsWindow.isReleasedWhenClosed = false
        statsWindow.titlebarAppearsTransparent = true
        statsWindow.titleVisibility = .hidden
        statsWindow.contentView = NSHostingView(rootView: StatisticsView().modelContext(modelContext))
        
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: statsWindow, queue: .main) { [weak statsWindow] _ in
            statsWindow?.close()
        }
        
        ContentView.statsWindow = statsWindow
        statsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func showResetConfirmation() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "危险操作：清空所有历史数据"
        alert.informativeText = "此操作将永久删除数据库中的所有活动日志。请在下方输入：“\(requiredConfirmText)”"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "确定清空")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        inputField.placeholderString = requiredConfirmText
        alert.accessoryView = inputField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if inputField.stringValue == requiredConfirmText {
                deleteAllData()
            } else {
                NSSound.beep()
            }
        }
    }
    
    private func deleteAllData() {
        do {
            let descriptor = FetchDescriptor<ActivityLog>()
            let allLogs = try modelContext.fetch(descriptor)
            for log in allLogs { modelContext.delete(log) }
            try modelContext.save()
            usageManager.currentWindowTodayDuration = 0
            usageManager.currentWindowHistoricalDuration = 0
        } catch {
            print("❌ [Database] 清空失败: \(error.localizedDescription)")
        }
    }
}

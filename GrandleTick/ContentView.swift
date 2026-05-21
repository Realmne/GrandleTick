import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    var usageManager: UsageManager
    
    static var statisticsWindow: NSWindow?
    static var whitelistWindow: NSWindow?
    
    private let requiredConfirmText = "我已知晓"
    
    private var isUntracked: Bool {
        usageManager.tracker.currentAppName.isEmpty
    }
    
    private var currentTitle: String {
        isUntracked ? "未追踪的窗口" : usageManager.tracker.currentWindowTitle
    }
    
    private var currentSourceName: String {
        isUntracked ? "其他应用 (非白名单)" : usageManager.tracker.currentAppName
    }
    
    private var durationHeadline: String {
        isUntracked ? "未在统计范围内" : "累计时长"
    }
    
    private var durationSubtitle: String {
        if isUntracked {
            return "切换到白名单内的应用或网站后会继续累计"
        }
        return currentSourceName
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if usageManager.tracker.currentWindowTitle == "需开启辅助功能权限" {
                Button(action: {
                    let accessibilitySettingsAddress = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(accessibilitySettingsAddress)
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
            
            VStack(alignment: .center, spacing: 12) {
                StatusPill(
                    text: isUntracked ? "已暂停统计" : "正在使用",
                    tint: isUntracked ? .gray : .blue,
                    systemImage: isUntracked ? "pause.fill" : "bolt.fill"
                )

                Image(systemName: isUntracked ? "pause.circle.fill" : "app.badge.checkmark.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isUntracked ? .gray : .blue)
                    .frame(width: 28, height: 28)

                VStack(spacing: 6) {
                    Text(currentTitle)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(currentSourceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.primary.opacity(0.05))
            )
            
            VStack(alignment: .center, spacing: 8) {
                Text(durationHeadline)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(usageManager.formattedPopoverDuration)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(isUntracked ? .gray : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(durationSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.primary.opacity(0.035))
            )
            
            VStack(spacing: 10) {
                ActionCapsuleButton(
                    title: "自定义白名单管理",
                    systemImage: "checklist",
                    tint: .blue,
                    action: openWhitelistWindow
                )

                ActionCapsuleButton(
                    title: "查看今日统计图表",
                    systemImage: "chart.pie.fill",
                    tint: .secondary,
                    action: openStatisticsWindow
                )

                ActionCapsuleButton(
                    title: "清空所有历史数据",
                    systemImage: "trash.fill",
                    tint: .red.opacity(0.8),
                    action: showResetConfirmation
                )
                
                Divider().padding(.horizontal, 40)
                
                ActionCapsuleButton(
                    title: "退出 GrandleTick",
                    systemImage: "power",
                    tint: .secondary,
                    action: { NSApplication.shared.terminate(nil) }
                )
            }
            .padding(.horizontal, 12)
        }
        .padding()
        .frame(width: 320)
    }
    
    func openWhitelistWindow() {
        if let existingWindow = ContentView.whitelistWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "白名单"
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
        if let existingWindow = ContentView.statisticsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let statisticsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        statisticsWindow.title = "统计"
        statisticsWindow.center()
        statisticsWindow.isReleasedWhenClosed = false
        statisticsWindow.titlebarAppearsTransparent = true
        statisticsWindow.titleVisibility = .hidden
        statisticsWindow.contentView = NSHostingView(rootView: StatisticsView().modelContext(modelContext))
        
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: statisticsWindow, queue: .main) { [weak statisticsWindow] _ in
            statisticsWindow?.close()
        }
        
        ContentView.statisticsWindow = statisticsWindow
        statisticsWindow.makeKeyAndOrderFront(nil)
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

private struct StatusPill: View {
    let text: String
    let tint: Color
    let systemImage: String
    
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct ActionCapsuleButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

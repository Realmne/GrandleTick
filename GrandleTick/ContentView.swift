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
    
    /// 区分当前正在活跃的窗口是属于“学习专注”还是“娱乐休闲”
    private var isStudyActive: Bool {
        guard !isUntracked else { return false }
        
        let appName = usageManager.tracker.currentAppName
        let windowTitle = usageManager.tracker.currentWindowTitle
        let domain = usageManager.tracker.currentDomain
        
        let lowercasedAppName = appName.lowercased()
        let isWebsite = lowercasedAppName.contains("safari") || lowercasedAppName.contains("chrome") || lowercasedAppName.contains("edge")
        
        // 1. 如果是浏览器，需要进一步校验域名是否在白名单内，并对 B 站做特殊处理。
        if isWebsite {
            guard let domain else { return false }
            let isWhitelistedDomain = WhitelistManager.shared.whitelistedDomains.contains { $0.lowercased() == domain.lowercased() }
            
            // B 站视频必须以 bilibiliIdentifier 非空为唯一判断依据：
            // - bilibiliIdentifier 只有在 API 确认为知识区（tidV2 在白名单中）时才会被赋值。
            // - 当 URL 获取失败走窗口标题兜底路径时，identifier 为 nil，
            //   此时 groupedTitle 可能是 "Bilibili" 而非 "娱乐"，不能用 groupedTitle 做判断，
            //   必须直接以 identifier 为准，否则所有 B 站内容都会被误归为学习。
            if domain == "bilibili.com" {
                return usageManager.tracker.currentBilibiliId != nil
            }
            
            return isWhitelistedDomain
        } 
        
        // 2. 如果是 macOS 预览 App，需要明确判断是否正在查看 PDF 文件以归为学习。
        if lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview") {
            return windowTitle.lowercased().contains(".pdf")
        } 
        
        // 3. 其他常规应用直接根据应用名称是否在白名单中来判断是否属于专注学习。
        return WhitelistManager.shared.whitelistedApps.contains { app in
            let lowercasedApp = app.lowercased()
            return lowercasedApp == lowercasedAppName || lowercasedApp.contains(lowercasedAppName) || lowercasedAppName.contains(lowercasedApp)
        }
    }
    
    private var currentTitle: String {
        isUntracked ? "未统计的窗口" : usageManager.tracker.currentWindowTitle
    }
    
    private var currentSourceName: String {
        isUntracked ? "其他应用（不在白名单）" : usageManager.tracker.currentAppName
    }
    
    private var durationHeadline: String {
        if isUntracked {
            return "未在统计范围内"
        }
        return isStudyActive ? "今日学习总时长" : "今日休闲总时长"
    }
    
    private var durationSubtitle: String {
        if isUntracked {
            return "切换到白名单内的应用或网站后会继续累计"
        }
        return isStudyActive ? "今日学习累计" : "今日休闲累计"
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
                        Text("前往开启辅助功能权限")
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
                    text: isUntracked ? "已暂停统计" : (isStudyActive ? "学习中" : "休闲中"),
                    tint: isUntracked ? .gray : (isStudyActive ? .blue : .purple),
                    systemImage: isUntracked ? "pause.fill" : (isStudyActive ? "book.fill" : "gamecontroller.fill")
                )

                Image(systemName: isUntracked ? "pause.circle.fill" : (isStudyActive ? "book.closed.fill" : "gamecontroller.fill"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isUntracked ? .gray : (isStudyActive ? .blue : .purple))
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

                if let durationLabel = usageManager.currentContentDurationLabel {
                    VStack(spacing: 8) {
                        Divider()
                            .padding(.horizontal, 12)

                        HStack(spacing: 8) {
                            Label(durationLabel, systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            Spacer(minLength: 8)

                            Text(usageManager.formattedCurrentContentDuration)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(isStudyActive ? .blue : .purple)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.horizontal, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(durationLabel)
                        .accessibilityValue(usageManager.formattedCurrentContentDuration)
                    }
                }
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
                    .foregroundColor(isUntracked ? .gray : (isStudyActive ? .blue : .purple))
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
                    title: "管理白名单",
                    systemImage: "checklist",
                    tint: .blue,
                    action: openWhitelistWindow
                )

                ActionCapsuleButton(
                    title: "查看统计数据",
                    systemImage: "chart.pie.fill",
                    tint: .blue,
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
                    action: {
                        // 1. 退出前强制持久化当前活动 Session，确保退出时的数据能够写入 SQLite 数据库。
                        usageManager.flushPendingSession()
                        
                        // 2. 强行终止进程，防止任何打开的子窗口/Sheet（例如年度报告）拦截系统终止指令而导致退出受阻。
                        exit(0)
                    }
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
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            if ContentView.whitelistWindow === window {
                ContentView.whitelistWindow = nil
            }
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
            contentRect: NSRect(x: 0, y: 0, width: AppConfig.statisticsWidth, height: AppConfig.statisticsHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        statisticsWindow.title = "数据统计中心"
        statisticsWindow.center()
        statisticsWindow.isReleasedWhenClosed = false
        statisticsWindow.titlebarAppearsTransparent = false
        statisticsWindow.titleVisibility = .hidden
        statisticsWindow.contentView = NSHostingView(rootView: StatisticsView().modelContext(modelContext))
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: statisticsWindow, queue: .main) { _ in
            if ContentView.statisticsWindow === statisticsWindow {
                ContentView.statisticsWindow = nil
            }
        }
        
        ContentView.statisticsWindow = statisticsWindow
        statisticsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func showResetConfirmation() {
        // 1. 激活 App 并配置警告弹窗属性。
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "危险操作：清空所有历史数据"
        alert.informativeText = "此操作将永久删除数据库中的所有活动日志。请在下方输入：“\(requiredConfirmText)”"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "确定清空")
        alert.addButton(withTitle: "取消")
        
        // 2. 插入文本输入框作为辅助视图。
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        inputField.placeholderString = requiredConfirmText
        alert.accessoryView = inputField
        
        // 3. 以模态方式运行弹窗并根据输入文字判断是否执行清空。
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
            usageManager.restartTrackingAfterHistoryDeletion()
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
        .focusable(false)
        .focusEffectDisabled()
    }
}

import AppKit
import SwiftData
import SwiftUI

extension Notification.Name {
    static let featureWindowWillOpen = Notification.Name("GrandleTick.featureWindowWillOpen")
    static let todaySummaryShouldRefresh = Notification.Name("GrandleTick.todaySummaryShouldRefresh")
}

/// 菜单栏应用切换为普通应用后，仍显式兜底标准的 Command-W 关闭行为。
private final class FeatureWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// 统一管理从菜单栏打开的独立功能窗口，以及 Dock 显示状态。
@MainActor
final class FeatureWindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = FeatureWindowCoordinator()

    private var statisticsWindow: NSWindow?
    private var whitelistWindow: NSWindow?
    private var todaySummaryWindow: NSWindow?

    private override init() {
        super.init()
    }

    func openStatisticsWindow(modelContext: ModelContext) {
        // 1. 先关闭菜单栏弹层并切换为普通应用，使功能窗口拥有独立的 Dock 图标与标准菜单命令。
        prepareForFeatureWindowPresentation()

        // 2. 已有窗口时只需重新显示，避免重复创建统计引擎和窗口状态。
        if let statisticsWindow {
            present(statisticsWindow)
            return
        }

        // 3. 创建标准可关闭窗口；closable 样式会接入 macOS 的 Command-W 关闭命令。
        let window = FeatureWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppConfig.statisticsWidth,
                height: AppConfig.statisticsHeight
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        configure(window, title: "数据统计中心", titlebarAppearsTransparent: false)
        window.contentView = NSHostingView(
            rootView: StatisticsView().modelContext(modelContext)
        )

        statisticsWindow = window
        present(window)
    }

    func openWhitelistWindow(modelContext: ModelContext) {
        // 1. 白名单也作为真正的独立窗口打开，切换到其它应用时不再自动关闭。
        prepareForFeatureWindowPresentation()

        // 2. 复用仍存在的窗口，保留用户当前的滚动位置和输入状态。
        if let whitelistWindow {
            present(whitelistWindow)
            return
        }

        // 3. 创建与统计中心行为一致的标准窗口，并显式传递数据上下文。
        let window = FeatureWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure(window, title: "名单管理", titlebarAppearsTransparent: true)
        window.contentView = NSHostingView(
            rootView: WhitelistView().modelContext(modelContext)
        )

        whitelistWindow = window
        present(window)
    }

    func openTodaySummaryWindow(modelContext: ModelContext) {
        // 1. 今日总结沿用其它菜单功能的独立窗口行为，避免大段时间线受菜单栏弹层高度限制。
        prepareForFeatureWindowPresentation()

        // 2. 窗口已存在时通知内容刷新，确保再次点击入口能看到刚写入的当前会话。
        if let todaySummaryWindow {
            NotificationCenter.default.post(name: .todaySummaryShouldRefresh, object: nil)
            present(todaySummaryWindow)
            return
        }

        // 3. 创建可缩放的标准窗口；尺寸和留白使用现有设计系统，保持与数据中心一致。
        let window = FeatureWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppConfig.todaySummaryWidth,
                height: AppConfig.todaySummaryHeight
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        configure(window, title: "今日总结", titlebarAppearsTransparent: false)
        window.minSize = NSSize(width: 540, height: 520)
        window.contentView = NSHostingView(
            rootView: TodaySummaryView().modelContext(modelContext)
        )

        todaySummaryWindow = window
        present(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }

        // 1. 释放已关闭窗口，下一次从菜单栏点击时创建全新的功能界面。
        if statisticsWindow === closingWindow {
            statisticsWindow = nil
        }
        if whitelistWindow === closingWindow {
            whitelistWindow = nil
        }
        if todaySummaryWindow === closingWindow {
            todaySummaryWindow = nil
        }

        // 2. 等关闭事件完成后再检查其它功能窗口；全部关闭时隐藏 Dock 图标，但保留菜单栏进程。
        DispatchQueue.main.async { [weak self] in
            self?.restoreMenuBarOnlyModeIfNeeded()
        }
    }

    private func prepareForFeatureWindowPresentation() {
        NotificationCenter.default.post(name: .featureWindowWillOpen, object: nil)
        // 功能窗口打开时切换为 regular，确保窗口拥有独立 Dock tile 和标准窗口行为。
        NSApp.setActivationPolicy(.regular)
        applyDockIcon()

        // Dock tile 在激活策略切换后的下一轮事件循环才可能完成重建，因此需要再次覆盖系统占位图。
        DispatchQueue.main.async { [weak self] in
            self?.applyDockIcon()
        }
    }

    private func configure(_ window: NSWindow, title: String, titlebarAppearsTransparent: Bool) {
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = titlebarAppearsTransparent
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.managed)
        window.delegate = self
    }

    private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreMenuBarOnlyModeIfNeeded() {
        guard statisticsWindow == nil,
              whitelistWindow == nil,
              todaySummaryWindow == nil else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func applyDockIcon() {
        guard let iconURL = Bundle.main.url(forResource: "DockIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApp.applicationIconImage = icon
        NSApp.dockTile.display()
    }
}

import AppKit
import SwiftData
import SwiftUI

extension Notification.Name {
    static let featureWindowWillOpen = Notification.Name("GrandleTick.featureWindowWillOpen")
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
        configure(window, title: "白名单", titlebarAppearsTransparent: true)
        window.contentView = NSHostingView(
            rootView: WhitelistView().modelContext(modelContext)
        )

        whitelistWindow = window
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

        // 2. 等关闭事件完成后再检查其它功能窗口；全部关闭时隐藏 Dock 图标，但保留菜单栏进程。
        DispatchQueue.main.async { [weak self] in
            self?.restoreMenuBarOnlyModeIfNeeded()
        }
    }

    private func prepareForFeatureWindowPresentation() {
        NotificationCenter.default.post(name: .featureWindowWillOpen, object: nil)
        // 应用现在始终采用 regular 策略；这里仍做兜底，确保旧进程升级后首次打开窗口就能恢复 Dock 图标。
        NSApp.setActivationPolicy(.regular)
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
        guard statisticsWindow == nil, whitelistWindow == nil else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

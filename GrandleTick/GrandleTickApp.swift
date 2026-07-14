import SwiftUI
import SwiftData
import Foundation
import AppKit

@main
struct GrandleTickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let container: ModelContainer
    @State private var usageManager: UsageManager

    init() {
        // 1. 准备应用支持目录，用于存放 SQLite 数据库。
        let applicationSupportDirectoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let applicationDirectoryURL = applicationSupportDirectoryURL.appendingPathComponent("GrandleTick", isDirectory: true)

        if !FileManager.default.fileExists(atPath: applicationDirectoryURL.path) {
            try? FileManager.default.createDirectory(at: applicationDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        // 2. 初始化 SwiftData 容器并执行必要的数据库维护（索引安装、迁移、压缩）。
        let databaseFileURL = applicationDirectoryURL.appendingPathComponent("ActivityData.sqlite")
        let configuration = ModelConfiguration(url: databaseFileURL)

        do {
            container = try ModelContainer(for: ActivityLog.self, configurations: configuration)
            ActivityLogIndexInstaller.installIfNeeded(databaseURL: databaseFileURL)

            let context = container.mainContext
            LegacyStoreMigrator.migrateIfNeeded(context: context, appDirectoryURL: applicationDirectoryURL)
            ActivityLogCompactor.compactIfNeeded(context: context, appDirectoryURL: applicationDirectoryURL)
            
            // 3. 初始化核心管理器并将上下文注入到 AppDelegate。
            let manager = UsageManager(modelContext: context)
            _usageManager = State(initialValue: manager)
            appDelegate.configure(usageManager: manager, modelContext: context)

            Task.detached(priority: .utility) {
                // 4. 应用启动后后台预热已结束日期的统计缓存，让“今年/全部”等大范围视图尽量直接命中聚合表。
                ActivityAggregateCacheStore.prewarmClosedDays(
                    databaseURL: databaseFileURL,
                    whitelist: WhitelistSnapshot(whitelist: WhitelistManager.shared),
                    calendar: .current
                )
            }
        } catch {
            fatalError("无法初始化数据库容器: \(error)")
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .modelContainer(container)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var usageManager: UsageManager?
    private var modelContext: ModelContext?
    private var statusBarController: StatusBarController?

    func configure(usageManager: UsageManager, modelContext: ModelContext) {
        self.usageManager = usageManager
        self.modelContext = modelContext
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let usageManager, let modelContext else { return }
        // 1. 显式加载编译后的 icns，避免菜单栏应用动态切换到 Dock 时沿用系统占位图。
        if let iconURL = Bundle.main.url(forResource: "DockIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        // 2. 启动时保持菜单栏模式；打开独立功能窗口后再临时显示 Dock 图标。
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(
            usageManager: usageManager,
            modelContext: modelContext
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageManager?.flushPendingSession()
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let usageManager: UsageManager
    private let modelContext: ModelContext
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(usageManager: UsageManager, modelContext: ModelContext) {
        self.usageManager = usageManager
        self.modelContext = modelContext
        super.init()
        configureStatusItem()
        configurePopover()
        installPopoverCloseHandlers()
        bindUsageManager()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "GrandleTick")
        button.imagePosition = .imageLeft
        button.lineBreakMode = .byTruncatingTail
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: AppConfig.popoverWidth, height: AppConfig.popoverHeight)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(usageManager: usageManager)
                .modelContext(modelContext)
        )
    }

    private func installPopoverCloseHandlers() {
        // 1. 监听应用失去焦点，自动关闭弹出框。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // 2. 独立功能窗口打开前主动收起菜单栏弹层，避免弹层覆盖新窗口内容。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFeatureWindowWillOpen),
            name: .featureWindowWillOpen,
            object: nil
        )

        // 3. 安装本地事件监听，处理弹出框外的点击。
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.closePopoverIfNeeded(for: event)
            return event
        }

        // 4. 安装全局事件监听，确保在其它应用点击时也能关闭。
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func bindUsageManager() {
        usageManager.menuBarTitleDidChange = { [weak self] title in
            self?.applyStatusItemTitle(title)
        }
        applyStatusItemTitle(usageManager.formattedMenuDuration)
    }

    private func applyStatusItemTitle(_ title: String) {
        guard let button = statusItem.button else { return }
        button.title = title
    }

    @objc
    private func handleApplicationDidResignActive() {
        closePopover()
    }

    @objc
    private func handleFeatureWindowWillOpen() {
        closePopover()
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.animationBehavior = .none
        }
    }

    private func closePopoverIfNeeded(for event: NSEvent) {
        guard popover.isShown else { return }
        guard let popoverWindow = popover.contentViewController?.view.window else { return }

        if event.window !== popoverWindow {
            popover.performClose(nil)
        }
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }
}

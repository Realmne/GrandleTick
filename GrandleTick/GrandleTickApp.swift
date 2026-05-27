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
        do {
            let applicationSupportDirectoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let applicationDirectoryURL = applicationSupportDirectoryURL.appendingPathComponent("GrandleTick", isDirectory: true)

            if !FileManager.default.fileExists(atPath: applicationDirectoryURL.path) {
                try FileManager.default.createDirectory(at: applicationDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }

            let databaseFileURL = applicationDirectoryURL.appendingPathComponent("ActivityData.sqlite")
            let configuration = ModelConfiguration(url: databaseFileURL)

            container = try ModelContainer(for: ActivityLog.self, configurations: configuration)
            ActivityLogIndexInstaller.installIfNeeded(databaseURL: databaseFileURL)

            let context = container.mainContext
            LegacyStoreMigrator.migrateIfNeeded(context: context, appDirectoryURL: applicationDirectoryURL)
            ActivityLogCompactor.compactIfNeeded(context: context, appDirectoryURL: applicationDirectoryURL)
            let manager = UsageManager(modelContext: context)
            _usageManager = State(initialValue: manager)
            appDelegate.configure(usageManager: manager, modelContext: context)
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
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(usageManager: usageManager)
                .modelContext(modelContext)
        )
    }

    private func installPopoverCloseHandlers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.closePopoverIfNeeded(for: event)
            return event
        }

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

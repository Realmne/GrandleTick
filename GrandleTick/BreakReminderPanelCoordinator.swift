import AppKit
import SwiftUI

extension Notification.Name {
    static let breakReminderWillPresent = Notification.Name("GrandleTick.breakReminderWillPresent")
}

/// 非激活面板保证提醒置顶可见，同时不夺走用户正在使用应用的键盘焦点。
private final class BreakReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BreakReminderPanelCoordinator {
    private let reminderManager: BreakReminderManager
    private var panel: NSPanel?

    init(reminderManager: BreakReminderManager) {
        self.reminderManager = reminderManager
        reminderManager.reminderDidBecomeDue = { [weak self] focusDuration in
            self?.showReminder(focusDuration: focusDuration)
        }
    }

    func dismissReminder() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func showReminder(focusDuration: TimeInterval) {
        // 1. 若已有提醒则先销毁旧面板，避免系统唤醒和计时 tick 同时触发时出现重复窗口。
        dismissReminder()
        NotificationCenter.default.post(name: .breakReminderWillPresent, object: nil)

        // 2. 使用 borderless + nonactivatingPanel，窗口可以置顶并接收鼠标点击，但不会激活 App 或抢键盘焦点。
        let panelSize = NSSize(width: AppConfig.breakReminderWidth, height: AppConfig.breakReminderHeight)
        let panel = BreakReminderPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(
            rootView: BreakReminderView(
                focusDuration: focusDuration,
                onComplete: { [weak self] in
                    self?.dismissReminder()
                },
                onSnooze: { [weak self] in
                    guard let self else { return }
                    self.dismissReminder()
                    self.reminderManager.schedule(minutes: 5)
                }
            )
        )

        // 3. 以鼠标所在屏幕作为“当前屏幕”，并使用 visibleFrame 自动避开菜单栏和 Dock。
        let targetScreen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        if let visibleFrame = targetScreen?.visibleFrame {
            let origin = NSPoint(
                x: visibleFrame.maxX - panelSize.width - AppConfig.breakReminderScreenMargin,
                y: visibleFrame.maxY - panelSize.height - AppConfig.breakReminderScreenMargin
            )
            panel.setFrameOrigin(origin)
        }

        self.panel = panel
        NSSound(named: "Glass")?.play()
        panel.orderFrontRegardless()
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }
    }
}

private struct BreakReminderView: View {
    let focusDuration: TimeInterval
    let onComplete: () -> Void
    let onSnooze: () -> Void

    private var durationDescription: String {
        let minutes = max(1, Int((focusDuration / 60).rounded()))
        return "你已经连续专注 \(minutes) 分钟"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppDesign.successGreen)
                .frame(width: 42, height: 42)
                .background(AppDesign.successGreen.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                Text("该休息一下了")
                    .font(.system(size: 17, weight: .bold))

                Text(durationDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("完成休息", action: onComplete)
                        .buttonStyle(AppCapsuleButtonStyle(role: .primary, compact: true))

                    Button("延后 5 分钟", action: onSnooze)
                        .buttonStyle(AppCapsuleButtonStyle(role: .secondary, compact: true))
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: AppConfig.breakReminderWidth, height: AppConfig.breakReminderHeight)
        .background(.regularMaterial)
        .background(AppDesign.appBackground.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.largeCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.largeCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("休息提醒")
    }
}

import AppKit
import Foundation
import Observation

/// 管理单次休息提醒的截止时间、持久化和系统唤醒恢复。
@MainActor
@Observable
final class BreakReminderManager {
    private enum DefaultsKey {
        static let deadline = "breakReminder.deadline"
        static let scheduledDuration = "breakReminder.scheduledDuration"
    }

    private(set) var deadline: Date?
    private(set) var scheduledDuration: TimeInterval = 0
    private(set) var remainingDuration: TimeInterval = 0

    @ObservationIgnored
    var reminderDidBecomeDue: ((TimeInterval) -> Void)?

    @ObservationIgnored
    private var timer: Timer?

    @ObservationIgnored
    private var wakeObserver: NSObjectProtocol?

    @ObservationIgnored
    private var clockChangeObserver: NSObjectProtocol?

    var isScheduled: Bool {
        deadline != nil
    }

    var formattedRemainingDuration: String {
        let totalSeconds = max(0, Int(remainingDuration.rounded(.up)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    init() {
        installSystemTimeObservers()
    }

    deinit {
        timer?.invalidate()

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let clockChangeObserver {
            NotificationCenter.default.removeObserver(clockChangeObserver)
        }
    }

    func restorePersistedReminder() {
        // 1. 从 UserDefaults 恢复绝对截止时间，而不是恢复剩余秒数，避免应用退出期间倒计时停住。
        let defaults = UserDefaults.standard
        let persistedDeadlineInterval = defaults.double(forKey: DefaultsKey.deadline)
        guard persistedDeadlineInterval > 0 else {
            clearStateAndPersistence()
            return
        }

        deadline = Date(timeIntervalSince1970: persistedDeadlineInterval)
        scheduledDuration = max(0, defaults.double(forKey: DefaultsKey.scheduledDuration))

        // 2. 立即按当前时间校验；若应用关闭期间已经到点，启动后应马上补发提醒。
        refresh(at: Date())
        if deadline != nil {
            startTimer()
        }
    }

    func schedule(minutes: Int) {
        guard minutes > 0 else { return }

        // 1. 每次设置都生成新的绝对截止时间，延后提醒也复用同一条可靠计时路径。
        let duration = TimeInterval(minutes * 60)
        scheduledDuration = duration
        deadline = Date().addingTimeInterval(duration)
        remainingDuration = duration

        // 2. 先持久化再启动计时，确保应用意外退出时仍能在下次启动恢复。
        persistCurrentState()
        startTimer()
    }

    func cancel() {
        clearStateAndPersistence()
    }

    private func startTimer() {
        timer?.invalidate()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(at: Date())
            }
        }
        // 倒计时展示无需毫秒级精度，容差可让系统合并唤醒，降低菜单栏常驻时的能耗。
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh(at now: Date) {
        guard let deadline else {
            remainingDuration = 0
            timer?.invalidate()
            timer = nil
            return
        }

        // 使用 deadline - now 派生剩余时间，系统睡眠、计时器延迟或时间跳变都不会积累误差。
        let remaining = deadline.timeIntervalSince(now)
        guard remaining <= 0 else {
            remainingDuration = remaining
            return
        }

        let elapsedFocusDuration = scheduledDuration
        clearStateAndPersistence()
        reminderDidBecomeDue?(elapsedFocusDuration)
    }

    private func persistCurrentState() {
        guard let deadline else { return }
        let defaults = UserDefaults.standard
        defaults.set(deadline.timeIntervalSince1970, forKey: DefaultsKey.deadline)
        defaults.set(scheduledDuration, forKey: DefaultsKey.scheduledDuration)
    }

    private func clearStateAndPersistence() {
        timer?.invalidate()
        timer = nil
        deadline = nil
        scheduledDuration = 0
        remainingDuration = 0

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.deadline)
        defaults.removeObject(forKey: DefaultsKey.scheduledDuration)
    }

    private func installSystemTimeObservers() {
        // 1. Mac 从睡眠中恢复时，Timer 不会补跑所有丢失的 tick，因此必须主动按绝对截止时间重新判断。
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(at: Date())
            }
        }

        // 2. 用户手动修改系统时间或时区时同步刷新，避免界面长时间显示旧的剩余时间。
        clockChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(at: Date())
            }
        }
    }
}

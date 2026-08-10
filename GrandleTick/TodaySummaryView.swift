import SwiftUI

struct TodayTimelineEntry: Identifiable, Sendable {
    let id: String
    let appName: String
    let title: String
    let subtitle: String?
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let isStudy: Bool
}

struct TodaySummarySnapshot: Sendable {
    let entries: [TodayTimelineEntry]
    let studyDuration: TimeInterval
    let leisureDuration: TimeInterval

    static let empty = TodaySummarySnapshot(entries: [], studyDuration: 0, leisureDuration: 0)
}

enum TodaySummaryBuilder {
    private static let mergeGapTolerance: TimeInterval = 5

    static func build(
        now: Date,
        whitelist: WhitelistSnapshot,
        calendar: Calendar
    ) -> TodaySummarySnapshot {
        // 1. 只读取今天开始的原始记录，并裁剪超过当前时刻或今日边界的异常时段。
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return .empty
        }
        let interval = DateInterval(start: dayStart, end: dayEnd)
        let logs = ActivityLogSnapshotStore.fetchLogs(
            databaseURL: ActivityLogSnapshotStore.databaseURL(),
            interval: interval,
            includeOverlapping: true
        )
        .compactMap { PreparedLog(snapshot: $0, whitelist: whitelist, calendar: calendar) }
        .sorted { $0.startTime < $1.startTime }

        // 2. 把日志转换为可展示的时间段，并沿用统计中心的标题、域名和学习分类口径。
        var entries: [TodayTimelineEntry] = []
        for log in logs {
            let startTime = max(log.startTime, dayStart)
            let endTime = min(log.endTime, min(now, dayEnd))
            guard endTime > startTime else { continue }

            let subtitle = timelineSubtitle(for: log)
            let entry = TodayTimelineEntry(
                id: "\(log.identity.hashValue)-\(startTime.timeIntervalSinceReferenceDate)",
                appName: log.appName,
                title: log.windowTitle,
                subtitle: subtitle,
                startTime: startTime,
                endTime: endTime,
                duration: endTime.timeIntervalSince(startTime),
                isStudy: log.isStudy
            )

            // 同一活动可能因定期持久化或旧版数据迁移留下紧邻片段；仅合并五秒内的同类片段，
            // 避免时间线把一次连续活动拆成多个视觉上重复的卡片。
            if let previous = entries.last,
               canMerge(previous, entry),
               entry.startTime.timeIntervalSince(previous.endTime) <= mergeGapTolerance {
                entries[entries.count - 1] = TodayTimelineEntry(
                    id: previous.id,
                    appName: previous.appName,
                    title: previous.title,
                    subtitle: previous.subtitle,
                    startTime: previous.startTime,
                    endTime: max(previous.endTime, entry.endTime),
                    duration: max(previous.endTime, entry.endTime).timeIntervalSince(previous.startTime),
                    isStudy: previous.isStudy
                )
            } else {
                entries.append(entry)
            }
        }

        // 3. 基于最终展示片段计算概览，保证顶部总时长与下方时间线严格一致。
        let studyDuration = entries.filter(\.isStudy).reduce(0) { $0 + $1.duration }
        let leisureDuration = entries.filter { !$0.isStudy }.reduce(0) { $0 + $1.duration }
        return TodaySummarySnapshot(
            entries: entries.reversed(),
            studyDuration: studyDuration,
            leisureDuration: leisureDuration
        )
    }

    private static func timelineSubtitle(for log: PreparedLog) -> String? {
        if let domain = log.resolvedDomain, domain.caseInsensitiveCompare(log.appName) != .orderedSame {
            return "\(log.appName) · \(domain)"
        }
        return log.appName == log.windowTitle ? nil : log.appName
    }

    private static func canMerge(_ lhs: TodayTimelineEntry, _ rhs: TodayTimelineEntry) -> Bool {
        lhs.appName == rhs.appName
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.isStudy == rhs.isStudy
    }
}

struct TodaySummaryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot = TodaySummarySnapshot.empty
    @State private var isLoading = true
    @State private var contentVisible = false
    @State private var refreshTask: Task<Void, Never>?

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            AppDesign.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isLoading && snapshot.entries.isEmpty {
                    loadingState
                } else if snapshot.entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                            overview
                            timeline
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                        .opacity(contentVisible ? 1 : 0)
                        .offset(y: reduceMotion || contentVisible ? 0 : 6)
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 520)
        .onAppear {
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .todaySummaryShouldRefresh)) { _ in
            refresh()
        }
        .onReceive(Timer.publish(every: 60, tolerance: 8, on: .main, in: .default).autoconnect()) { _ in
            refresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日总结")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppDesign.primaryText)

                Text(formatToday(Date()))
                    .font(.caption)
                    .foregroundStyle(AppDesign.secondaryText)
            }

            Spacer()

            Label("\(snapshot.entries.count) 个时间段", systemImage: "clock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppDesign.websiteTeal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppDesign.websiteTeal.opacity(0.10)))
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(title: "今天的时间分布", subtitle: "按实际记录的活动时段汇总", compact: true)

            HStack(spacing: 12) {
                TodaySummaryMetric(
                    title: "学习专注",
                    duration: snapshot.studyDuration,
                    systemImage: "book.closed.fill",
                    tint: AppDesign.primaryBlue
                )
                TodaySummaryMetric(
                    title: "休闲活动",
                    duration: snapshot.leisureDuration,
                    systemImage: "gamecontroller.fill",
                    tint: AppDesign.leisurePurple
                )
                TodaySummaryMetric(
                    title: "已记录",
                    duration: snapshot.studyDuration + snapshot.leisureDuration,
                    systemImage: "timer",
                    tint: AppDesign.websiteTeal
                )
            }
        }
        .appPanel(.regular)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(title: "活动时间线", subtitle: "最近的活动显示在最上方", compact: true)

            VStack(spacing: 0) {
                ForEach(Array(snapshot.entries.enumerated()), id: \.element.id) { index, entry in
                    TodayTimelineRow(entry: entry, isLast: index == snapshot.entries.count - 1)
                }
            }
        }
        .appPanel(.regular)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("正在整理今天的活动…")
                .font(.caption)
                .foregroundStyle(AppDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 42))
                .foregroundStyle(AppDesign.secondaryText.opacity(0.45))
            Text("今天还没有活动记录")
                .font(.headline)
            Text("使用已纳入统计的应用或网站后，这里会按时间段生成总结。")
                .font(.caption)
                .foregroundStyle(AppDesign.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() {
        refreshTask?.cancel()
        isLoading = true
        let whitelist = WhitelistSnapshot(whitelist: WhitelistManager.shared)
        let now = Date()
        let calendar = calendar

        // 数据读取和时间段整理放到后台执行，避免打开窗口时阻塞菜单栏和主线程动画。
        refreshTask = Task {
            let refreshedSnapshot = await Task.detached(priority: .userInitiated) {
                TodaySummaryBuilder.build(now: now, whitelist: whitelist, calendar: calendar)
            }.value
            guard !Task.isCancelled else { return }

            snapshot = refreshedSnapshot
            isLoading = false
            withAnimation(reduceMotion ? nil : AppDesign.animationCurve) {
                contentVisible = true
            }
        }
    }

    private func formatToday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: date)
    }
}

private struct TodaySummaryMetric: View {
    let title: String
    let duration: TimeInterval
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            Text(formatDuration(duration))
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(AppDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.mediumCornerRadius, style: .continuous)
                .fill(AppDesign.tintedSurface(tint, opacity: 0.11))
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)时\(minutes)分" : "\(minutes)分钟"
    }
}

private struct TodayTimelineRow: View {
    let entry: TodayTimelineEntry
    let isLast: Bool

    private var tint: Color {
        entry.isStudy ? AppDesign.primaryBlue : AppDesign.leisurePurple
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(tint.opacity(0.20), lineWidth: 4))

                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.09))
                        .frame(width: 1)
                        .frame(minHeight: 58)
                }
            }
            .padding(.top, 5)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(formatTimeRange(entry))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint)

                    Spacer()

                    Text(formatDuration(entry.duration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppDesign.secondaryText)
                }

                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppDesign.primaryText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(entry.isStudy ? "学习" : "休闲")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)

                    if let subtitle = entry.subtitle {
                        Text("·")
                        Text(subtitle)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(AppDesign.tertiaryText)
            }
            .padding(.bottom, isLast ? 0 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatTimeRange(_ entry: TodayTimelineEntry) -> String {
        // 很短的切换片段如果只显示到分钟，会出现起止时间完全相同；此时补充秒数才能真实表达时间段。
        let formatter = DateFormatter()
        formatter.dateFormat = entry.duration < 60 ? "HH:mm:ss" : "HH:mm"
        return "\(formatter.string(from: entry.startTime)) – \(formatter.string(from: entry.endTime))"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)时\(minutes)分" : "\(hours)小时"
        }
        return minutes > 0 ? "\(minutes)分钟" : "不足1分钟"
    }
}

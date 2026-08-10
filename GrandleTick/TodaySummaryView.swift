import SwiftUI

struct TodayAppUsage: Identifiable, Sendable {
    let identity: String
    let displayName: String
    let sourceName: String?
    let duration: TimeInterval
    let studyDuration: TimeInterval
    let leisureDuration: TimeInterval
    let detailSummary: String?

    var id: String { identity }
}

struct TodayTimeBlock: Identifiable, Sendable {
    let startTime: Date
    let endTime: Date
    let totalDuration: TimeInterval
    let appUsages: [TodayAppUsage]

    var id: Date { startTime }
}

struct TodaySummarySnapshot: Sendable {
    let blocks: [TodayTimeBlock]
    let studyDuration: TimeInterval
    let leisureDuration: TimeInterval

    static let empty = TodaySummarySnapshot(blocks: [], studyDuration: 0, leisureDuration: 0)
}

private struct TodayAppUsageAccumulator {
    let identity: String
    let displayName: String
    let sourceName: String?
    var duration: TimeInterval = 0
    var studyDuration: TimeInterval = 0
    var leisureDuration: TimeInterval = 0
    var detailDurations: [String: TimeInterval] = [:]

    mutating func add(log: PreparedLog, duration: TimeInterval) {
        self.duration += duration
        if log.isStudy {
            studyDuration += duration
        } else {
            leisureDuration += duration
        }

        let detail = TodaySummaryBuilder.detailName(for: log)
        detailDurations[detail, default: 0] += duration
    }

    func build() -> TodayAppUsage {
        // 详情只展示耗时最高的三个内容，避免浏览器标签页较多时挤占 App 用时主体。
        let details = detailDurations
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(3)
            .map(\.key)

        return TodayAppUsage(
            identity: identity,
            displayName: displayName,
            sourceName: sourceName,
            duration: duration,
            studyDuration: studyDuration,
            leisureDuration: leisureDuration,
            detailSummary: details.isEmpty ? nil : details.joined(separator: "、")
        )
    }
}

enum TodaySummaryBuilder {
    static func build(
        now: Date,
        whitelist: WhitelistSnapshot,
        calendar: Calendar
    ) -> TodaySummarySnapshot {
        // 1. 读取与今天相交的日志，并沿用数据中心既有的分类与内容标准化规则。
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

        // 2. 把每条日志裁剪到今天，并在跨越整点时拆分到对应的自然小时。
        // 这样快速切换窗口只会增加小时块内的 App 用时，不会制造大量秒级时间线条目。
        var hourlyApps: [Date: [String: TodayAppUsageAccumulator]] = [:]
        var studyDuration: TimeInterval = 0
        var leisureDuration: TimeInterval = 0

        for log in logs {
            var segmentStart = max(log.startTime, dayStart)
            let logEnd = min(log.endTime, min(now, dayEnd))
            guard logEnd > segmentStart else { continue }

            while segmentStart < logEnd {
                guard let hourInterval = calendar.dateInterval(of: .hour, for: segmentStart) else { break }
                let segmentEnd = min(logEnd, hourInterval.end)
                let segmentDuration = segmentEnd.timeIntervalSince(segmentStart)
                guard segmentDuration > 0 else { break }

                let usageIdentity = usageIdentity(for: log)
                var apps = hourlyApps[hourInterval.start, default: [:]]
                var appUsage = apps[usageIdentity] ?? TodayAppUsageAccumulator(
                    identity: usageIdentity,
                    displayName: displayName(for: log),
                    sourceName: websiteDomain(for: log) == nil ? nil : log.appName
                )
                appUsage.add(log: log, duration: segmentDuration)
                apps[usageIdentity] = appUsage
                hourlyApps[hourInterval.start] = apps

                if log.isStudy {
                    studyDuration += segmentDuration
                } else {
                    leisureDuration += segmentDuration
                }
                segmentStart = segmentEnd
            }
        }

        // 3. 每个小时内按 App 总用时降序排列，小时块则按最近优先展示。
        var blocks: [TodayTimeBlock] = []
        for (hourStart, appAccumulators) in hourlyApps {
            guard let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { continue }
            var appUsages = appAccumulators.values.map { $0.build() }
            appUsages.sort { lhs, rhs in
                if lhs.duration == rhs.duration {
                    return lhs.displayName < rhs.displayName
                }
                return lhs.duration > rhs.duration
            }
            let totalDuration = appUsages.reduce(TimeInterval.zero) { partialResult, usage in
                partialResult + usage.duration
            }
            blocks.append(TodayTimeBlock(
                startTime: hourStart,
                endTime: min(hourEnd, now),
                totalDuration: totalDuration,
                appUsages: appUsages
            ))
        }
        blocks.sort { $0.startTime > $1.startTime }

        return TodaySummarySnapshot(
            blocks: blocks,
            studyDuration: studyDuration,
            leisureDuration: leisureDuration
        )
    }

    static func detailName(for log: PreparedLog) -> String {
        log.windowTitle == log.appName ? log.appName : log.windowTitle
    }

    private static func usageIdentity(for log: PreparedLog) -> String {
        // 浏览器按域名而不是浏览器 App 聚合，避免查阅多个网站时全部被折叠为 Chrome。
        if let domain = websiteDomain(for: log) {
            return "domain:\(domain.lowercased())"
        }
        return "app:\(log.appName.lowercased())"
    }

    private static func displayName(for log: PreparedLog) -> String {
        websiteDomain(for: log) ?? log.appName
    }

    private static func websiteDomain(for log: PreparedLog) -> String? {
        // 某些旧版原生 App 日志可能残留 domain 元数据；只有浏览器日志才能按网站拆分。
        log.isWebsite ? log.resolvedDomain : nil
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

                if isLoading && snapshot.blocks.isEmpty {
                    loadingState
                } else if snapshot.blocks.isEmpty {
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

            Label("\(snapshot.blocks.count) 个时段", systemImage: "clock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppDesign.primaryBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppDesign.primaryBlue.opacity(0.11)))
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
            AppSectionHeader(
                title: "分时段 App 用时",
                subtitle: "按小时汇总，切换窗口不会拆散同一时段",
                compact: true
            )

            LazyVStack(spacing: 12) {
                ForEach(snapshot.blocks) { block in
                    TodayTimeBlockCard(block: block)
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

        // 数据读取和小时聚合放到后台执行，避免打开窗口时阻塞菜单栏和主线程动画。
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
}

private struct TodayTimeBlockCard: View {
    let block: TodayTimeBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(formatTimeBlock(block), systemImage: "clock")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppDesign.primaryBlue)

                Spacer()

                Text("已记录 \(formatDuration(block.totalDuration))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppDesign.secondaryText)
            }

            VStack(spacing: 10) {
                ForEach(Array(block.appUsages.enumerated()), id: \.element.id) { index, usage in
                    TodayAppUsageRow(
                        usage: usage,
                        totalDuration: block.totalDuration,
                        tint: AppDesign.chartPalette[index % AppDesign.chartPalette.count]
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.mediumCornerRadius, style: .continuous)
                .fill(AppDesign.elevatedPanelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.mediumCornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.045), lineWidth: 1)
                )
        )
    }

    private func formatTimeBlock(_ block: TodayTimeBlock) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: block.startTime)) – \(formatter.string(from: block.endTime))"
    }
}

private struct TodayAppUsageRow: View {
    let usage: TodayAppUsage
    let totalDuration: TimeInterval
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "macwindow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(usage.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppDesign.primaryText)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(AppDesign.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatDuration(usage.duration))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppDesign.primaryText)

                    Text(categorySummary)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppDesign.secondaryText)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.055))
                    Capsule()
                        .fill(tint.opacity(0.72))
                        .frame(width: proxy.size.width * usageRatio)
                }
            }
            .frame(height: 4)
        }
    }

    private var usageRatio: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, usage.duration / totalDuration)))
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let sourceName = usage.sourceName,
           !sourceName.isEmpty,
           sourceName != usage.displayName {
            parts.append(sourceName)
        }
        if let detailSummary = usage.detailSummary,
           !detailSummary.isEmpty,
           detailSummary != usage.displayName {
            parts.append(detailSummary)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var categorySummary: String {
        let hasStudy = usage.studyDuration >= 1
        let hasLeisure = usage.leisureDuration >= 1
        if hasStudy && hasLeisure {
            return "学习 \(formatDuration(usage.studyDuration)) · 休闲 \(formatDuration(usage.leisureDuration))"
        }
        return hasStudy ? "学习" : "休闲"
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60

    if hours > 0 {
        return minutes > 0 ? "\(hours)时\(minutes)分" : "\(hours)小时"
    }
    if minutes > 0 {
        return "\(minutes)分钟"
    }
    return "不足1分钟"
}

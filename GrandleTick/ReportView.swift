import SwiftUI
import SwiftData
import Charts

struct ReportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var whitelist = WhitelistManager.shared
    @State private var selectedPeriod: ReportPeriod = .week
    @State private var selectedReferenceDate = Date()
    @State private var selectedPage: ReportPage = .cover
    @State private var snapshot: ReportSnapshot?

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.96, blue: 0.92),
                    Color(red: 0.93, green: 0.96, blue: 0.98),
                    Color(red: 0.98, green: 0.95, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if let snapshot {
                        if snapshot.hasData {
                            ScrollView {
                                pageView(for: snapshot)
                                    .padding(.horizontal, 28)
                                    .padding(.top, 20)
                                    .padding(.bottom, 28)
                            }
                            .scrollIndicators(.hidden)
                        } else {
                            emptyStateView
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(minWidth: 860, minHeight: 640)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear(perform: refreshSnapshot)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshSnapshot()
        }
        .onChange(of: whitelist.whitelistedApps) { _, _ in refreshSnapshot() }
        .onChange(of: whitelist.whitelistedDomains) { _, _ in refreshSnapshot() }
        .onChange(of: selectedPeriod) { _, _ in
            refreshSnapshot()
        }
    }

    private var headerPager: some View {
        HStack(spacing: 10) {
            ReportPagerButton(
                systemImage: "chevron.left",
                isDisabled: selectedPage == .cover,
                action: showPreviousPage
            )

            ReportPagerButton(
                systemImage: "chevron.right",
                isDisabled: selectedPage == .rhythm,
                action: showNextPage
            )
        }
    }

    private var canShowNextPeriod: Bool {
        let now = Date()
        let selectedInterval = selectedPeriod.reportInterval(containing: selectedReferenceDate, currentDate: now, calendar: calendar)
        let currentInterval = selectedPeriod.reportInterval(containing: now, currentDate: now, calendar: calendar)
        return selectedInterval.start < currentInterval.start
    }

    @ViewBuilder
    private func pageView(for snapshot: ReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            switch selectedPage {
            case .cover:
                ReportCoverPage(
                    snapshot: snapshot,
                    formatDuration: formatDetailedDuration,
                    formatDateRange: formatDateRange,
                    header: AnyView(
                        ReportPageHeader(
                            selectedPeriod: $selectedPeriod,
                            rangeText: formatDateRange(snapshot.interval),
                            canShowNextPeriod: canShowNextPeriod,
                            previousPeriod: showPreviousPeriod,
                            nextPeriod: showNextPeriod,
                            label: "总览",
                            title: snapshot.period.reportTitle,
                            subtitle: nil,
                            pager: AnyView(headerPager)
                        )
                    )
                )
            case .appChampion:
                ReportAppChampionPage(
                    snapshot: snapshot,
                    formatDuration: formatCompactDuration,
                    header: AnyView(
                        ReportPageHeader(
                            selectedPeriod: $selectedPeriod,
                            rangeText: formatDateRange(snapshot.interval),
                            canShowNextPeriod: canShowNextPeriod,
                            previousPeriod: showPreviousPeriod,
                            nextPeriod: showNextPeriod,
                            label: "热度最高 App",
                            title: snapshot.topApps.first.map { "热度最高的 App 是 \($0.name)" } ?? "热度最高 App",
                            subtitle: snapshot.topApps.isEmpty ? nil : snapshot.appFocusSummary,
                            pager: AnyView(headerPager)
                        )
                    )
                )
            case .sources:
                ReportSourcesPage(
                    snapshot: snapshot,
                    formatDuration: formatCompactDuration,
                    header: AnyView(
                        ReportPageHeader(
                            selectedPeriod: $selectedPeriod,
                            rangeText: formatDateRange(snapshot.interval),
                            canShowNextPeriod: canShowNextPeriod,
                            previousPeriod: showPreviousPeriod,
                            nextPeriod: showNextPeriod,
                            label: "常看内容",
                            title: "这段时间你主要在看什么",
                            subtitle: "网站和 PDF 会放在一起看",
                            pager: AnyView(headerPager)
                        )
                    )
                )
            case .peakDay:
                ReportPeakDayPage(
                    snapshot: snapshot,
                    formatDuration: formatCompactDuration,
                    formatDay: formatLongDate,
                    header: AnyView(
                        ReportPageHeader(
                            selectedPeriod: $selectedPeriod,
                            rangeText: formatDateRange(snapshot.interval),
                            canShowNextPeriod: canShowNextPeriod,
                            previousPeriod: showPreviousPeriod,
                            nextPeriod: showNextPeriod,
                            label: "高峰日",
                            title: snapshot.strongestDay.map { "\(formatLongDate($0.date)) 是你学得最久的一天" } ?? "高峰日",
                            subtitle: snapshot.strongestDay.map { "这一天一共学了 \(formatCompactDuration($0.totalTime))" },
                            pager: AnyView(headerPager)
                        )
                    )
                )
            case .rhythm:
                ReportRhythmPage(
                    snapshot: snapshot,
                    formatDuration: formatCompactDuration,
                    formatDay: formatShortDate,
                    formatLongDay: formatLongDate,
                    formatClock: formatClock,
                    header: AnyView(
                        ReportPageHeader(
                            selectedPeriod: $selectedPeriod,
                            rangeText: formatDateRange(snapshot.interval),
                            canShowNextPeriod: canShowNextPeriod,
                            previousPeriod: showPreviousPeriod,
                            nextPeriod: showNextPeriod,
                            label: "学习节奏",
                            title: "学习节奏",
                            subtitle: "看看你通常在什么时间进入状态",
                            pager: AnyView(headerPager)
                        )
                    )
                )
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "book.closed.circle")
                .font(.system(size: 46, weight: .light))
                .foregroundColor(.secondary.opacity(0.45))
            Text("\(selectedPeriod.title)还没有学习记录")
                .font(.system(size: 22, weight: .bold))
            Text("切换到白名单内的应用或网站后，这里会自动整理出 5 页回顾。")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func refreshSnapshot() {
        let logs = fetchLogsForSelectedPeriod()
        snapshot = ReportBuilder.build(
            period: selectedPeriod,
            logs: logs,
            whitelist: whitelist,
            referenceDate: selectedReferenceDate,
            now: Date(),
            calendar: calendar
        )
    }

    private func fetchLogsForSelectedPeriod() -> [ActivityLog] {
        let now = Date()
        let currentInterval = selectedPeriod.reportInterval(containing: selectedReferenceDate, currentDate: now, calendar: calendar)
        let previousInterval = selectedPeriod.previousInterval(before: currentInterval, calendar: calendar)
        let start = previousInterval?.start ?? currentInterval.start
        let end = currentInterval.end

        let descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { log in
                log.startTime >= start && log.startTime < end
            },
            sortBy: [SortDescriptor(\ActivityLog.startTime, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("[Report] Failed to fetch logs: \(error.localizedDescription)")
            return []
        }
    }

    private func showPreviousPeriod() {
        shiftSelectedPeriod(by: -1)
    }

    private func showNextPeriod() {
        guard canShowNextPeriod else { return }
        shiftSelectedPeriod(by: 1)
    }

    private func shiftSelectedPeriod(by value: Int) {
        // 1. 先根据当前报告粒度确定要移动的日历单位。
        let component: Calendar.Component

        switch selectedPeriod {
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .year:
            component = .year
        }

        // 2. 再计算目标周期的参考日期，失败时保持当前报告不变。
        guard let nextDate = calendar.date(byAdding: component, value: value, to: selectedReferenceDate) else {
            return
        }

        // 3. 最后写回参考日期并刷新快照，让内容、趋势和对比数据同步更新。
        selectedReferenceDate = nextDate
        refreshSnapshot()
    }

    private func showPreviousPage() {
        guard let previous = ReportPage(rawValue: selectedPage.rawValue - 1) else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            selectedPage = previous
        }
    }

    private func showNextPage() {
        guard let next = ReportPage(rawValue: selectedPage.rawValue + 1) else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            selectedPage = next
        }
    }

    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let roundedSeconds = max(0, Int(seconds.rounded()))
        let hours = roundedSeconds / 3600
        let minutes = (roundedSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        return "\(minutes)分"
    }

    private func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let roundedSeconds = max(0, Int(seconds.rounded()))
        let hours = roundedSeconds / 3600
        let minutes = (roundedSeconds % 3600) / 60
        let remainingSeconds = roundedSeconds % 60

        if hours > 0 {
            return String(format: "%02d小时%02d分%02d秒", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d分%02d秒", minutes, remainingSeconds)
    }

    private func formatShortDate(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    private func formatLongDate(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    private func formatDateRange(_ interval: DateInterval) -> String {
        let endDate = interval.end.addingTimeInterval(-1)
        return "\(formatShortDate(interval.start)) - \(formatShortDate(endDate))"
    }

    private func formatClock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

private enum ReportPage: Int, CaseIterable, Identifiable {
    case cover
    case appChampion
    case sources
    case peakDay
    case rhythm

    var id: Int { rawValue }
    var index: Int { rawValue }

    var title: String {
        switch self {
        case .cover: return "总览"
        case .appChampion: return "热度最高 App"
        case .sources: return "内容来源"
        case .peakDay: return "高峰日"
        case .rhythm: return "学习节奏"
        }
    }
}

private struct ReportCoverPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let formatDateRange: (DateInterval) -> String
    let header: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(formatDuration(snapshot.totalDuration))
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                    Text(snapshot.coverSummary)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 12) {
                    ReportMiniBadge(title: "活跃天数", value: "\(snapshot.activeDays) 天")
                    ReportMiniBadge(title: "日均时长", value: formatDuration(snapshot.averageDailyDuration))
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.90, green: 0.94, blue: 1.0),
                                Color(red: 1.0, green: 0.96, blue: 0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )

            HStack(spacing: 16) {
                ReportMetricCard(title: "活跃天数", value: "\(snapshot.activeDays) 天", subtitle: snapshot.period.title, tint: .green)
                ReportMetricCard(title: "日均学习", value: formatDuration(snapshot.averageDailyDuration), subtitle: "按活跃天计算", tint: .orange)
                ReportMetricCard(title: "记录范围", value: formatDateRange(snapshot.interval), subtitle: "截至今天", tint: .blue)
            }

            ReportBalanceCard(
                studyDuration: snapshot.totalDuration,
                entertainmentDuration: snapshot.entertainmentDuration,
                formatDuration: formatDuration
            )
        }
    }
}

private struct ReportPageHeader: View {
    @Binding var selectedPeriod: ReportPeriod
    let rangeText: String
    let canShowNextPeriod: Bool
    let previousPeriod: () -> Void
    let nextPeriod: () -> Void
    let label: String
    let title: String
    let subtitle: String?
    let pager: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                HStack(spacing: 10) {
                    Text("报告周期")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    Picker("报告周期", selection: $selectedPeriod) {
                        ForEach(ReportPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                Spacer()

                HStack(spacing: 8) {
                    ReportPagerButton(
                        systemImage: "chevron.left",
                        isDisabled: false,
                        action: previousPeriod
                    )

                    Text(rangeText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 96)

                    ReportPagerButton(
                        systemImage: "chevron.right",
                        isDisabled: !canShowNextPeriod,
                        action: nextPeriod
                    )
                }

                pager
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.title3.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct ReportAppChampionPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let header: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            if let champion = snapshot.topApps.first {
                ReportHighlightCard(
                    title: champion.name,
                    value: formatDuration(champion.totalTime),
                    subtitle: "占总时长 \(shareText(champion.share))",
                    tint: .blue
                )
            }

            ReportRankingPanel(
                title: "用得最多的 3 个 App",
                items: snapshot.topApps,
                formatDuration: formatDuration
            )
        }
    }

    private func shareText(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}

private struct ReportSourcesPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let header: AnyView

    private var secondaryItems: [ReportRankItem] {
        snapshot.topPDFs.isEmpty ? snapshot.topItems : snapshot.topPDFs
    }

    private var secondaryTitle: String {
        snapshot.topPDFs.isEmpty ? "最常看的 3 个内容" : "最常看的 3 份 PDF"
    }

    var body: some View {
        let hasPrimary = !snapshot.topDomains.isEmpty
        let hasSecondary = !secondaryItems.isEmpty

        VStack(alignment: .leading, spacing: 22) {
            header

            if hasPrimary && hasSecondary {
                HStack(alignment: .top, spacing: 18) {
                    ReportRankingPanel(
                        title: "最常看的 3 个网站",
                        items: snapshot.topDomains,
                        formatDuration: formatDuration
                    )

                    ReportRankingPanel(
                        title: secondaryTitle,
                        items: secondaryItems,
                        formatDuration: formatDuration
                    )
                }
            } else if hasPrimary {
                ReportRankingPanel(
                    title: "最常看的 3 个网站",
                    items: snapshot.topDomains,
                    formatDuration: formatDuration
                )
            } else if hasSecondary {
                ReportRankingPanel(
                    title: secondaryTitle,
                    items: secondaryItems,
                    formatDuration: formatDuration
                )
            } else {
                ReportPlaceholderCard(
                    title: "这段时间还没有足够的内容记录",
                    subtitle: "有了网站或 PDF 记录后，这一页会自动补全。"
                )
            }
        }
    }
}

private struct ReportPeakDayPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let formatDay: (Date) -> String
    let header: AnyView

    private var maxHours: Double {
        let peakHours = snapshot.trendPoints.map { $0.totalTime / 3600 }.max() ?? 0
        if peakHours <= 2 {
            return 2
        }
        return ceil(peakHours)
    }

    private var yAxisStride: Double {
        maxHours <= 4 ? 1 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            VStack(alignment: .leading, spacing: 16) {
                Text(snapshot.trendGranularity == .month ? "月度趋势" : "每日趋势")
                    .font(.headline)

                Chart(snapshot.trendPoints) { point in
                    BarMark(
                        x: .value("日期", axisLabel(for: point.date)),
                        y: .value("时长", point.totalTime / 3600)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(5)
                }
                .frame(height: 280)
                .chartXScale(domain: snapshot.trendPoints.map { axisLabel(for: $0.date) })
                .chartYScale(domain: 0 ... maxHours)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: yAxisStride)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text(yAxisLabel(for: hours))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: snapshot.trendPoints.map { axisLabel(for: $0.date) }) { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                            }
                        }
                    }
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.white.opacity(0.72))
            )
        }
    }

    private func axisLabel(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)

        switch snapshot.trendGranularity {
        case .day:
            return "\(components.month ?? 0)/\(components.day ?? 0)"
        case .month:
            return "\(components.month ?? 0)月"
        }
    }

    private func yAxisLabel(for hours: Double) -> String {
        if hours == 0 {
            return "0小时"
        }

        if hours.rounded(.towardZero) == hours {
            return "\(Int(hours))小时"
        }

        return "\(hours.formatted(.number.precision(.fractionLength(1))))小时"
    }
}

private struct ReportRhythmPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let formatDay: (Date) -> String
    let formatLongDay: (Date) -> String
    let formatClock: (Date) -> String
    let header: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            HStack(spacing: 16) {
                ReportMetricCard(title: "最长连续学习", value: "\(snapshot.longestStreak) 天", subtitle: "最长连续活跃区间", tint: .purple)
                ReportMetricCard(title: "活跃天数", value: "\(snapshot.activeDays) 天", subtitle: snapshot.period.title, tint: .green)
                ReportMetricCard(title: "主要时段", value: snapshot.primaryTimeSlot?.title ?? "暂无", subtitle: "按开始时间统计", tint: .orange)
            }

            HStack(spacing: 16) {
                ReportClockCard(
                    title: "最早开始",
                    value: snapshot.earliestStudyStart.map(formatClock) ?? "暂无",
                    subtitle: snapshot.earliestStudyStart.map(formatLongDay) ?? "暂无记录"
                )
                ReportClockCard(
                    title: "最晚结束",
                    value: snapshot.latestStudyEnd.map(formatClock) ?? "暂无",
                    subtitle: snapshot.latestStudyEnd.map(formatLongDay) ?? "暂无记录"
                )
            }

            HStack(alignment: .top, spacing: 18) {
                ReportDaySummaryCard(
                    title: "最长学习日",
                    stat: snapshot.strongestDay,
                    formatDuration: formatDuration,
                    formatDay: formatDay
                )

                ReportDaySummaryCard(
                    title: "最短学习日",
                    stat: snapshot.shortestActiveDay,
                    formatDuration: formatDuration,
                    formatDay: formatDay
                )
            }
        }
    }
}

private struct ReportMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct ReportBalanceCard: View {
    let studyDuration: TimeInterval
    let entertainmentDuration: TimeInterval
    let formatDuration: (TimeInterval) -> String

    private var totalDuration: TimeInterval {
        studyDuration + entertainmentDuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("时间分布")
                .font(.headline)

            GeometryReader { geometry in
                let studyRatio = totalDuration > 0 ? studyDuration / totalDuration : 1
                let entertainmentRatio = max(0, 1 - studyRatio)

                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.blue.opacity(0.65))
                        .frame(width: max(geometry.size.width * studyRatio, studyDuration > 0 ? 24 : 0), height: 12)

                    if entertainmentDuration > 0 {
                        Capsule()
                            .fill(Color.orange.opacity(0.55))
                            .frame(width: max(geometry.size.width * entertainmentRatio, 20), height: 12)
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 18) {
                ReportLegendStat(title: "学习时间", value: formatDuration(studyDuration), tint: .blue)
                ReportLegendStat(title: "娱乐时间", value: formatDuration(entertainmentDuration), tint: .orange)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.white.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct ReportHighlightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("热度最高 App")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.18),
                            Color.white.opacity(0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct ReportClockCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct ReportRankingPanel: View {
    let title: String
    let items: [ReportRankItem]
    let formatDuration: (TimeInterval) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            if items.isEmpty {
                Text("暂无数据")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(index + 1). \(item.name)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatDuration(item.totalTime))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(height: 10)

                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: max(geometry.size.width * item.share, 10), height: 10)
                                }
                            }
                            .frame(height: 10)

                            Text("占比 \(Int((item.share * 100).rounded()))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.white.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct ReportDaySummaryCard: View {
    let title: String
    let stat: ReportDayStat?
    let formatDuration: (TimeInterval) -> String
    let formatDay: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let stat {
                Text(formatDay(stat.date))
                    .font(.system(size: 22, weight: .bold))
                Text(formatDuration(stat.totalTime))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.secondary)
            } else {
                Text("暂无数据")
                    .foregroundColor(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.white.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct ReportPlaceholderCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.white.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct ReportMiniBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.56))
        )
    }
}

private struct ReportPagerButton: View {
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(isDisabled ? 0.38 : 0.86))
                .frame(width: 34, height: 34)
                .background(backgroundFill)
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: 0.8)
                )
                .scaleEffect(isPressed && !isDisabled ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            guard !isDisabled else {
                isHovered = false
                return
            }

            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .pressing { pressing in
            guard !isDisabled else {
                isPressed = false
                return
            }

            withAnimation(.easeOut(duration: 0.08)) {
                isPressed = pressing
            }
        }
    }

    private var backgroundFill: some View {
        Circle()
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isDisabled {
            return Color.white.opacity(0.34)
        }
        if isPressed {
            return Color.white.opacity(0.96)
        }
        if isHovered {
            return Color.white.opacity(0.90)
        }
        return Color.white.opacity(0.72)
    }

    private var borderColor: Color {
        if isDisabled {
            return Color.black.opacity(0.04)
        }
        return Color.black.opacity(isHovered ? 0.10 : 0.07)
    }
}

private extension View {
    func pressing(_ onPress: @escaping (Bool) -> Void) -> some View {
        buttonStyle(PressObserverStyle(onPress: onPress))
    }
}

private struct PressObserverStyle: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPress(isPressed)
            }
    }
}

private struct ReportLegendStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint.opacity(0.75))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        }
    }
}

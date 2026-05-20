import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivityLog.startTime, order: .reverse) private var allLogs: [ActivityLog]

    @State private var whitelist = WhitelistManager.shared
    @State private var selectedRange: StatisticsRange = .last7Days
    @State private var selectedDimension: RankingDimension = .app
    @State private var selectedDay: Date?
    @State private var rangeLogs: [ActivityLog] = []
    @State private var daySummaries: [DaySummary] = []
    @State private var rankingEntriesCache: [RankingEntry] = []
    @State private var rangeTotalDuration: TimeInterval = 0
    @State private var selectedDayDuration: TimeInterval = 0
    @State private var selectedDayAppSummaries: [GroupedSummary] = []
    @State private var selectedDayDomainSummaries: [GroupedSummary] = []
    @State private var selectedDayPdfSummaries: [GroupedSummary] = []

    private let calendar = Calendar.current

    var body: some View {
        let effectiveSelectedDay = resolvedSelectedDay(from: daySummaries)

        VStack(spacing: 0) {
            headerView(totalDuration: rangeTotalDuration)
            if rangeLogs.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        overviewCards(
                            totalDuration: rangeTotalDuration,
                            activeDays: daySummaries.count,
                            selectedDay: effectiveSelectedDay,
                            selectedDayDuration: selectedDayDuration
                        )

                        RangeTrendSection(
                            daySummaries: daySummaries,
                            selectedDay: effectiveSelectedDay,
                            onSelectDay: { selectedDay = $0 },
                            formatDuration: formatCompactDuration
                        )

                        DayPickerSection(
                            daySummaries: daySummaries,
                            selectedDay: effectiveSelectedDay,
                            onSelect: { selectedDay = $0 },
                            formatDuration: formatCompactDuration,
                            formatDate: formatShortDate
                        )

                        RankingSection(
                            selectedDimension: $selectedDimension,
                            rankingEntries: rankingEntriesCache,
                            formatDuration: formatCompactDuration
                        )

                        SelectedDaySection(
                            selectedDay: effectiveSelectedDay,
                            appSummaries: selectedDayAppSummaries,
                            domainSummaries: selectedDayDomainSummaries,
                            pdfSummaries: selectedDayPdfSummaries,
                            formatDuration: formatCompactDuration,
                            formatDate: formatLongDate,
                            onDelete: { category, summaryName, detailName in
                                deleteLogs(
                                    on: effectiveSelectedDay,
                                    category: category,
                                    summaryName: summaryName,
                                    detailName: detailName
                                )
                            }
                        )
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 640, height: 760)
        .ignoresSafeArea(.all, edges: .top)
        .onAppear { refreshRangeData() }
        .onChange(of: allLogs) { _, _ in refreshRangeData() }
        .onChange(of: whitelist.whitelistedApps) { _, _ in refreshRangeData() }
        .onChange(of: whitelist.whitelistedDomains) { _, _ in refreshRangeData() }
        .onChange(of: selectedRange) { _, _ in refreshRangeData() }
        .onChange(of: selectedDimension) { _, _ in refreshRankingEntries() }
        .onChange(of: selectedDay) { _, _ in refreshSelectedDayData() }
    }

    @ViewBuilder
    private func headerView(totalDuration: TimeInterval) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("历史复盘")
                        .font(.system(size: 22, weight: .bold))
                    Text("把自动采集的数据真正用起来")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(selectedRange.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDetailedDuration(totalDuration))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
            }

            Picker("时间范围", selection: $selectedRange) {
                ForEach(StatisticsRange.allCases) { range in
                    Text(range.shortTitle).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .background(Material.regular)
        .overlay(Divider(), alignment: .bottom)
    }

    @ViewBuilder
    private func overviewCards(
        totalDuration: TimeInterval,
        activeDays: Int,
        selectedDay: Date?,
        selectedDayDuration: TimeInterval
    ) -> some View {
        HStack(spacing: 12) {
            OverviewCard(
                title: "范围总时长",
                value: formatDetailedDuration(totalDuration),
                subtitle: selectedRange.title,
                tint: .blue
            )

            OverviewCard(
                title: "活跃天数",
                value: "\(activeDays)",
                subtitle: activeDays == 1 ? "1 day" : "\(activeDays) days",
                tint: .green
            )

            OverviewCard(
                title: "当前选中",
                value: formatCompactDuration(selectedDayDuration),
                subtitle: selectedDay.map(formatLongDate) ?? "暂无日期",
                tint: .orange
            )
        }
    }

    private func eligibleLogs(from logs: [ActivityLog]) -> [ActivityLog] {
        logs.filter { log in
            if log.windowTitle.contains("权限") || log.windowTitle.contains("未知") || log.appName.isEmpty {
                return false
            }

            let lowercasedAppName = log.appName.lowercased()
            let isBrowser = isBrowserApp(log.appName)

            let isWhitelistedApp = whitelist.whitelistedApps.contains { whitelistedApp in
                let lowercasedWhitelistedApp = whitelistedApp.lowercased()
                return lowercasedWhitelistedApp == lowercasedAppName
                    || lowercasedWhitelistedApp.contains(lowercasedAppName)
                    || lowercasedAppName.contains(lowercasedWhitelistedApp)
            }

            if !isWhitelistedApp {
                return false
            }

            if isBrowser {
                let lowercasedWindowTitle = log.windowTitle.lowercased()
                if lowercasedWindowTitle.contains("网页加载中") {
                    return true
                }
                return browserDomain(for: log) != nil
            }

            return true
        }
    }

    private func dailySummaries(for logs: [ActivityLog]) -> [DaySummary] {
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.startTime) }
        return grouped.map { date, dayLogs in
            DaySummary(date: date, totalTime: dayLogs.reduce(0) { $0 + $1.duration })
        }
        .sorted { $0.date < $1.date }
    }

    private func rankingEntries(for logs: [ActivityLog], dimension: RankingDimension) -> [RankingEntry] {
        let grouped = Dictionary(grouping: logs) { log in
            rankingKey(for: log, dimension: dimension)
        }

        return grouped.compactMap { key, groupedLogs in
            guard let key else { return nil }
            return RankingEntry(name: key, totalTime: groupedLogs.reduce(0) { $0 + $1.duration })
        }
        .sorted {
            if $0.totalTime == $1.totalTime {
                return $0.name < $1.name
            }
            return $0.totalTime > $1.totalTime
        }
    }

    private func groupedSummaries(for logs: [ActivityLog], dimension: RankingDimension) -> [GroupedSummary] {
        let grouped = Dictionary(grouping: logs) { log in
            rankingKey(for: log, dimension: dimension)
        }

        return grouped.compactMap { key, groupedLogs in
            guard let key else { return nil }

            let detailGroups = Dictionary(grouping: groupedLogs) { detailKey(for: $0, dimension: dimension) }
            let details = detailGroups.map { detailKey, detailLogs in
                SummaryDetail(
                    name: detailKey,
                    subtitle: detailSubtitle(for: detailLogs, dimension: dimension),
                    totalTime: detailLogs.reduce(0) { $0 + $1.duration }
                )
            }
            .sorted {
                if $0.totalTime == $1.totalTime {
                    return $0.name < $1.name
                }
                return $0.totalTime > $1.totalTime
            }

            return GroupedSummary(
                name: key,
                totalTime: groupedLogs.reduce(0) { $0 + $1.duration },
                details: details
            )
        }
        .sorted {
            if $0.totalTime == $1.totalTime {
                return $0.name < $1.name
            }
            return $0.totalTime > $1.totalTime
        }
    }

    private func logs(for selectedDay: Date?, in logs: [ActivityLog]) -> [ActivityLog] {
        guard let selectedDay else { return [] }
        return logs.filter { calendar.isDate($0.startTime, inSameDayAs: selectedDay) }
    }

    private func rankingKey(for log: ActivityLog, dimension: RankingDimension) -> String? {
        switch dimension {
        case .app:
            return log.appName
        case .domain:
            return browserDomain(for: log)
        case .item:
            return log.windowTitle
        }
    }

    private func detailKey(for log: ActivityLog, dimension: RankingDimension) -> String {
        switch dimension {
        case .app:
            return log.windowTitle
        case .domain:
            return log.windowTitle
        case .item:
            return browserDomain(for: log) ?? log.appName
        }
    }

    private func detailSubtitle(for logs: [ActivityLog], dimension: RankingDimension) -> String? {
        guard dimension == .item else { return nil }

        let sources = Set(logs.map { browserDomain(for: $0) ?? $0.appName }).sorted()
        guard !sources.isEmpty else { return nil }
        return sources.joined(separator: " · ")
    }

    private func pdfSummaries(for logs: [ActivityLog]) -> [GroupedSummary] {
        let pdfLogs = logs.filter { isPDFLog($0) }
        let grouped = Dictionary(grouping: pdfLogs) { $0.windowTitle }

        return grouped.map { title, titleLogs in
            GroupedSummary(
                name: title,
                totalTime: titleLogs.reduce(0) { $0 + $1.duration },
                details: [
                    SummaryDetail(
                        name: title,
                        subtitle: titleLogs.first?.appName,
                        totalTime: titleLogs.reduce(0) { $0 + $1.duration }
                    )
                ]
            )
        }
        .sorted {
            if $0.totalTime == $1.totalTime {
                return $0.name < $1.name
            }
            return $0.totalTime > $1.totalTime
        }
    }

    private func browserDomain(for log: ActivityLog) -> String? {
        if let domain = log.domain, whitelist.whitelistedDomains.contains(domain) {
            return domain
        }

        let lowercasedWindowTitle = log.windowTitle.lowercased()
        return whitelist.whitelistedDomains.first { domain in
            let keyword = domain.components(separatedBy: ".").first?.lowercased() ?? domain.lowercased()
            return lowercasedWindowTitle.contains(keyword)
                || (keyword == "bilibili" && lowercasedWindowTitle.contains("哔哩哔哩"))
        }
    }

    private func isBrowserApp(_ appName: String) -> Bool {
        let lowercasedAppName = appName.lowercased()
        return lowercasedAppName.contains("safari")
            || lowercasedAppName.contains("chrome")
            || lowercasedAppName.contains("edge")
    }

    private func isPDFLog(_ log: ActivityLog) -> Bool {
        let lowercasedAppName = log.appName.lowercased()
        let lowercasedTitle = log.windowTitle.lowercased()
        return (lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview"))
            && lowercasedTitle.contains(".pdf")
    }

    private func resolvedSelectedDay(from daySummaries: [DaySummary]) -> Date? {
        guard !daySummaries.isEmpty else { return nil }

        if let selectedDay,
           daySummaries.contains(where: { calendar.isDate($0.date, inSameDayAs: selectedDay) }) {
            return selectedDay
        }

        return daySummaries.last?.date
    }

    private func refreshRangeData() {
        let eligible = eligibleLogs(from: allLogs)
        let newRangeLogs = eligible.filter { selectedRange.contains($0.startTime, calendar: calendar) }
        let newDaySummaries = dailySummaries(for: newRangeLogs)

        rangeLogs = newRangeLogs
        daySummaries = newDaySummaries
        rangeTotalDuration = newRangeLogs.reduce(0) { $0 + $1.duration }

        let resolvedDay = resolvedSelectedDay(from: newDaySummaries)
        if !isSameDay(selectedDay, resolvedDay) {
            selectedDay = resolvedDay
        } else {
            refreshSelectedDayData()
        }

        refreshRankingEntries()
    }

    private func refreshRankingEntries() {
        rankingEntriesCache = rankingEntries(for: rangeLogs, dimension: selectedDimension)
    }

    private func refreshSelectedDayData() {
        let effectiveSelectedDay = resolvedSelectedDay(from: daySummaries)
        let selectedLogs = logs(for: effectiveSelectedDay, in: rangeLogs)

        selectedDayDuration = selectedLogs.reduce(0) { $0 + $1.duration }
        selectedDayAppSummaries = groupedSummaries(for: selectedLogs, dimension: .app)
        selectedDayDomainSummaries = groupedSummaries(for: selectedLogs, dimension: .domain)
        selectedDayPdfSummaries = pdfSummaries(for: selectedLogs)
    }

    private func isSameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            return calendar.isDate(left, inSameDayAs: right)
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private func deleteLogs(on selectedDay: Date?, category: DetailCategory, summaryName: String, detailName: String) {
        guard let selectedDay else { return }

        let logsToDelete = logs(for: selectedDay, in: rangeLogs).filter { log in
            switch category {
            case .app:
                return rankingKey(for: log, dimension: .app) == summaryName
                    && detailKey(for: log, dimension: .app) == detailName
            case .domain:
                return rankingKey(for: log, dimension: .domain) == summaryName
                    && detailKey(for: log, dimension: .domain) == detailName
            case .pdf:
                return isPDFLog(log) && log.windowTitle == summaryName && log.windowTitle == detailName
            }
        }

        guard !logsToDelete.isEmpty else { return }

        for log in logsToDelete {
            modelContext.delete(log)
        }

        try? modelContext.save()
        refreshRangeData()
    }

    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let remainingSeconds = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%02dh %02dm %02ds", hours, minutes, remainingSeconds)
        }
        return String(format: "%02dm %02ds", minutes, remainingSeconds)
    }

    private func formatShortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day())
    }

    private func formatLongDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.defaultDigits).day())
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.35))
            Text("当前时间范围内还没有可复盘的记录")
                .font(.headline)
            Text("切换一下范围，或者先去白名单内的应用和网站累计一些数据。")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum StatisticsRange: String, CaseIterable, Identifiable {
    case today
    case last7Days
    case last30Days
    case all

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .today: return "今天"
        case .last7Days: return "7天"
        case .last30Days: return "30天"
        case .all: return "全部"
        }
    }

    var title: String {
        switch self {
        case .today: return "今天"
        case .last7Days: return "最近 7 天"
        case .last30Days: return "最近 30 天"
        case .all: return "全部历史"
        }
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let startOfToday = calendar.startOfDay(for: Date())

        switch self {
        case .today:
            return calendar.isDate(date, inSameDayAs: startOfToday)
        case .last7Days:
            guard let startDate = calendar.date(byAdding: .day, value: -6, to: startOfToday) else {
                return true
            }
            return date >= startDate
        case .last30Days:
            guard let startDate = calendar.date(byAdding: .day, value: -29, to: startOfToday) else {
                return true
            }
            return date >= startDate
        case .all:
            return true
        }
    }
}

private enum RankingDimension: String, CaseIterable, Identifiable {
    case app
    case domain
    case item

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return "应用"
        case .domain: return "网站"
        case .item: return "具体条目"
        }
    }
}

private enum DetailCategory {
    case app
    case domain
    case pdf
}

private struct DaySummary: Identifiable {
    let date: Date
    let totalTime: TimeInterval

    var id: Date { date }
}

private struct RankingEntry: Identifiable {
    let name: String
    let totalTime: TimeInterval

    var id: String { name }
}

private struct GroupedSummary: Identifiable {
    let name: String
    let totalTime: TimeInterval
    let details: [SummaryDetail]

    var id: String { name }
}

private struct SummaryDetail: Identifiable {
    let name: String
    let subtitle: String?
    let totalTime: TimeInterval

    var id: String { "\(name)|\(subtitle ?? "")" }
}

private struct OverviewCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "circle.fill")
                .font(.caption)
                .foregroundColor(.secondary)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(tint.opacity(0.10))
        )
    }
}

private struct RangeTrendSection: View {
    let daySummaries: [DaySummary]
    let selectedDay: Date?
    let onSelectDay: (Date) -> Void
    let formatDuration: (TimeInterval) -> String

    @State private var highlightedDay: Date?
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("每日总时长趋势")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("点柱子切换日期")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart(daySummaries) { daySummary in
                BarMark(
                    x: .value("日期", daySummary.date, unit: .day),
                    y: .value("时长", daySummary.totalTime / 3600)
                )
                .foregroundStyle(isHighlighted(daySummary.date) ? Color.accentColor : Color.accentColor.opacity(0.35))
                .cornerRadius(5)
                .annotation(position: .top, alignment: .center) {
                    if isHighlighted(daySummary.date) {
                        Text(formatDuration(daySummary.totalTime))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 220)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.month(.defaultDigits).day()))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                }
            }

            if let strongestDay = daySummaries.max(by: { $0.totalTime < $1.totalTime }) {
                HStack {
                    Text("最高峰")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(strongestDay.date.formatted(.dateTime.month(.defaultDigits).day()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(strongestDay.totalTime))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(20)
        .onAppear {
            highlightedDay = selectedDay
        }
        .onChange(of: selectedDay) { _, newValue in
            commitTask?.cancel()
            if !isSameDay(highlightedDay, newValue) {
                highlightedDay = newValue
            }
        }
        .onDisappear {
            commitTask?.cancel()
        }
    }

    private func isHighlighted(_ date: Date) -> Bool {
        guard let highlightedDay else { return false }
        return Calendar.current.isDate(date, inSameDayAs: highlightedDay)
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame.map({ geometry[$0] }) else { return }
        let relativeX = location.x - plotFrame.origin.x

        guard relativeX >= 0, relativeX <= plotFrame.size.width else { return }

        let nearest = daySummaries
            .compactMap { daySummary -> (summary: DaySummary, distance: CGFloat)? in
                guard let centerDate = Calendar.current.date(byAdding: .hour, value: 12, to: daySummary.date),
                      let positionX = proxy.position(forX: centerDate) else {
                    return nil
                }
                return (daySummary, abs(positionX - relativeX))
            }
            .min { $0.distance < $1.distance }

        if let nearest, !isHighlighted(nearest.summary.date) {
            highlightedDay = nearest.summary.date
            scheduleCommit(for: nearest.summary.date)
        }
    }

    private func scheduleCommit(for date: Date) {
        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onSelectDay(date)
            }
        }
    }

    private func isSameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            return Calendar.current.isDate(left, inSameDayAs: right)
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}

private struct DayPickerSection: View {
    let daySummaries: [DaySummary]
    let selectedDay: Date?
    let onSelect: (Date) -> Void
    let formatDuration: (TimeInterval) -> String
    let formatDate: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("按天查看")
                .font(.system(size: 18, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(daySummaries.sorted { $0.date > $1.date }) { daySummary in
                        Button(action: { onSelect(daySummary.date) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(formatDate(daySummary.date))
                                    .font(.system(size: 13, weight: .semibold))
                                Text(formatDuration(daySummary.totalTime))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isSelected(daySummary.date) ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDay else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selectedDay)
    }
}

private struct RankingSection: View {
    @Binding var selectedDimension: RankingDimension
    let rankingEntries: [RankingEntry]
    let formatDuration: (TimeInterval) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("范围排行")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }

            Picker("排行维度", selection: $selectedDimension) {
                ForEach(RankingDimension.allCases) { dimension in
                    Text(dimension.title).tag(dimension)
                }
            }
            .pickerStyle(.segmented)

            if rankingEntries.isEmpty {
                Text("当前维度下没有可展示的数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(rankingEntries.prefix(8).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.accentColor.opacity(0.14)))

                            Text(entry.name)
                                .lineLimit(1)

                            Spacer()

                            Text(formatDuration(entry.totalTime))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(20)
    }
}

private struct SelectedDaySection: View {
    let selectedDay: Date?
    let appSummaries: [GroupedSummary]
    let domainSummaries: [GroupedSummary]
    let pdfSummaries: [GroupedSummary]
    let formatDuration: (TimeInterval) -> String
    let formatDate: (Date) -> String
    let onDelete: (DetailCategory, String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当天明细")
                        .font(.system(size: 18, weight: .semibold))
                    Text(selectedDay.map(formatDate) ?? "暂无日期")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if appSummaries.isEmpty && domainSummaries.isEmpty && pdfSummaries.isEmpty {
                Text("这一天没有可展开的记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 12) {
                    CategorySummaryGroup(
                        title: "应用",
                        emptyText: "这一天没有应用记录",
                        summaries: appSummaries,
                        formatDuration: formatDuration,
                        onDelete: { summaryName, detailName in
                            onDelete(.app, summaryName, detailName)
                        }
                    )

                    CategorySummaryGroup(
                        title: "域名",
                        emptyText: "这一天没有域名记录",
                        summaries: domainSummaries,
                        formatDuration: formatDuration,
                        onDelete: { summaryName, detailName in
                            onDelete(.domain, summaryName, detailName)
                        }
                    )

                    CategorySummaryGroup(
                        title: "PDF",
                        emptyText: "这一天没有 PDF 记录",
                        summaries: pdfSummaries,
                        formatDuration: formatDuration,
                        onDelete: { summaryName, detailName in
                            onDelete(.pdf, summaryName, detailName)
                        }
                    )
                }
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(20)
    }
}

private struct CategorySummaryGroup: View {
    let title: String
    let emptyText: String
    let summaries: [GroupedSummary]
    let formatDuration: (TimeInterval) -> String
    let onDelete: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            if summaries.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(summaries) { summary in
                    SummaryEntryCardView(
                        summary: summary,
                        formatDuration: formatDuration,
                        onDelete: { detailName in
                            onDelete(summary.name, detailName)
                        }
                    )
                }
            }
        }
    }
}

private struct SummaryEntryCardView: View {
    let summary: GroupedSummary
    let formatDuration: (TimeInterval) -> String
    let onDelete: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(summary.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(summary.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(formatDuration(summary.totalTime))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                ForEach(summary.details) { detail in
                    HStack(alignment: .top) {
                        Text("•")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detail.name)
                                .font(.system(size: 12))
                                .foregroundColor(.primary.opacity(0.76))
                                .lineLimit(2)
                            if let subtitle = detail.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(formatDuration(detail.totalTime))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.85))
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(detail.name)
                        } label: {
                            Label("删除此条记录", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.5))
        .cornerRadius(16)
    }
}

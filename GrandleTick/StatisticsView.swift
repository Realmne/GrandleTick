import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var engine = StatisticsEngine()
    @State private var whitelist = WhitelistManager.shared
    @State private var selectedRange: StatisticsRange = .last7Days
    @State private var selectedDimension: RankingDimension = .app
    @State private var searchText: String = ""
    @State private var selectedContentFilter: ContentFilter = .all
    @State private var selectedAppFilter: String?
    @State private var selectedDomainFilter: String?
    @State private var searchDebounceTask: Task<Void, Never>?

    private let calendar = Calendar.current

    var body: some View {
        let hasBaseRangeData = !engine.baseRangeLogs.isEmpty

        VStack(spacing: 0) {
            headerView(totalDuration: engine.rangeTotalDuration)
            if !hasBaseRangeData {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        FilterSection(
                            searchText: $searchText,
                            selectedContentFilter: $selectedContentFilter,
                            selectedAppFilter: $selectedAppFilter,
                            selectedDomainFilter: $selectedDomainFilter,
                            appOptions: engine.appFilterOptions,
                            domainOptions: engine.domainFilterOptions,
                            formatDuration: formatCompactDuration
                        )

                        if engine.rangeLogs.isEmpty {
                            filteredEmptyStateView
                        } else {
                            overviewCards(
                                totalDuration: engine.rangeTotalDuration,
                                activeDays: engine.daySummaries.count,
                                todayDuration: engine.todayDuration,
                                topAppSummary: engine.topAppSummary
                            )

                            RangeTrendSection(
                                daySummaries: engine.daySummaries,
                                selectedDay: engine.selectedDay,
                                onSelectDay: { engine.updateSelectedDay($0) },
                                formatDuration: formatCompactDuration
                            )

                            DayPickerSection(
                                daySummaries: engine.daySummaries,
                                selectedDay: engine.selectedDay,
                                onSelect: { engine.updateSelectedDay($0) },
                                formatDuration: formatCompactDuration,
                                formatDate: formatShortDate
                            )

                            SelectedDaySection(
                                selectedDay: engine.selectedDay,
                                appSummaries: engine.selectedDayAppSummaries,
                                domainSummaries: engine.selectedDayDomainSummaries,
                                pdfSummaries: engine.selectedDayPdfSummaries,
                                formatDuration: formatCompactDuration,
                                formatDate: formatLongDate,
                                onDelete: { category, summaryName, detailName in
                                    deleteLogs(
                                        on: engine.selectedDay,
                                        category: category,
                                        summaryName: summaryName,
                                        detailName: detailName
                                    )
                                }
                            )

                            RankingSection(
                                selectedDimension: $selectedDimension,
                                rankingEntries: engine.rankingEntries,
                                formatDuration: formatCompactDuration
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: AppConfig.statisticsWidth, height: AppConfig.statisticsHeight)
        .ignoresSafeArea(.all, edges: .top)
        .onAppear { refreshRangeData() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshRangeData()
        }
        .onChange(of: whitelist.whitelistedApps) { _, _ in refreshRangeData() }
        .onChange(of: whitelist.whitelistedDomains) { _, _ in refreshRangeData() }
        .onChange(of: selectedRange) { _, _ in refreshRangeData() }
        .onChange(of: selectedDimension) { _, _ in engine.updateRanking(for: selectedDimension) }
        .onChange(of: searchText) { _, _ in scheduleSearchRefresh() }
        .onChange(of: selectedContentFilter) { _, _ in engine.applyFilters(searchText: searchText, contentFilter: selectedContentFilter, appFilter: selectedAppFilter, domainFilter: selectedDomainFilter, dimension: selectedDimension) }
        .onChange(of: selectedAppFilter) { _, _ in engine.applyFilters(searchText: searchText, contentFilter: selectedContentFilter, appFilter: selectedAppFilter, domainFilter: selectedDomainFilter, dimension: selectedDimension) }
        .onChange(of: selectedDomainFilter) { _, _ in engine.applyFilters(searchText: searchText, contentFilter: selectedContentFilter, appFilter: selectedAppFilter, domainFilter: selectedDomainFilter, dimension: selectedDimension) }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
    }

    @ViewBuilder
    private func headerView(totalDuration: TimeInterval) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("统计")
                        .font(.system(size: 22, weight: .bold))
                    Text("学习时间")
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
        todayDuration: TimeInterval,
        topAppSummary: AppDurationSummary?
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            OverviewCard(
                title: "总时长",
                value: formatDetailedDuration(totalDuration),
                subtitle: selectedRange.title,
                tint: .blue
            )

            OverviewCard(
                title: "活跃天数",
                value: "\(activeDays)",
                subtitle: "\(activeDays) 天",
                tint: .green
            )

            OverviewCard(
                title: "今日时长",
                value: formatCompactDuration(todayDuration),
                subtitle: "今天",
                tint: .orange
            )

            OverviewCard(
                title: "单应用最高累计时长",
                value: topAppSummary.map { formatCompactDuration($0.totalTime) } ?? "0分",
                subtitle: topAppSummary?.displayName ?? "无数据",
                tint: .pink
            )
        }
    }

    private func refreshRangeData() {
        engine.refreshBaseData(for: selectedRange, modelContext: modelContext, whitelist: whitelist)
        sanitizeFilterSelection()
        engine.applyFilters(
            searchText: searchText,
            contentFilter: selectedContentFilter,
            appFilter: selectedAppFilter,
            domainFilter: selectedDomainFilter,
            dimension: selectedDimension
        )
    }

    private func sanitizeFilterSelection() {
        if let selectedAppFilter,
           !engine.appFilterOptions.contains(where: { $0.name == selectedAppFilter }) {
            self.selectedAppFilter = nil
        }

        if let selectedDomainFilter,
           !engine.domainFilterOptions.contains(where: { $0.name == selectedDomainFilter }) {
            self.selectedDomainFilter = nil
        }
    }

    private func deleteLogs(on selectedDay: Date?, category: DetailCategory, summaryName: String, detailName: String) {
        guard let selectedDay else { return }

        // 1. 根据当前 UI 筛选条件定位出需要删除的日志记录。
        let logsToDelete = engine.rangeLogs.filter { prepared in
            calendar.isDate(prepared.startTime, inSameDayAs: selectedDay) && {
                switch category {
                case .app:
                    return prepared.appName == summaryName && prepared.windowTitle == detailName
                case .domain:
                    return prepared.resolvedDomain == summaryName && (prepared.resolvedDomain ?? prepared.appName) == detailName
                case .pdf:
                    return prepared.isPDF && prepared.windowTitle == summaryName && prepared.windowTitle == detailName
                }
            }()
        }.map { $0.identity }

        guard !logsToDelete.isEmpty else { return }

        // 2. 在 ModelContext 中执行删除并持久化。
        for identity in logsToDelete {
            let start = identity.startTime
            let duration = identity.duration
            let appName = identity.appName
            let windowTitle = identity.windowTitle
            let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { log in
                log.startTime == start && log.duration == duration && log.appName == appName && log.windowTitle == windowTitle
            })
            if let logs = try? modelContext.fetch(descriptor), let log = logs.first {
                modelContext.delete(log)
            }
        }

        // 3. 最后重新触发引擎数据刷新，确保 UI 与数据库状态同步。
        try? modelContext.save()
        refreshRangeData()
    }

    private func scheduleSearchRefresh() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                engine.applyFilters(
                    searchText: searchText,
                    contentFilter: selectedContentFilter,
                    appFilter: selectedAppFilter,
                    domainFilter: selectedDomainFilter,
                    dimension: selectedDimension
                )
            }
        }
    }

    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)时\(minutes)分" : "\(minutes)分"
    }

    private func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let remainingSeconds = Int(seconds) % 60
        return hours > 0
            ? String(format: "%02d时%02d分%02d秒", hours, minutes, remainingSeconds)
            : String(format: "%02d分%02d秒", minutes, remainingSeconds)
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
            Text("当前范围无记录")
                .font(.headline)
            Text("请先在白名单应用或网站中使用。")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.35))
            Text("无匹配记录")
                .font(.headline)
            Text("请调整筛选条件。")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("清空筛选") {
                clearFilters()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func clearFilters() {
        searchDebounceTask?.cancel()
        searchText = ""
        selectedContentFilter = .all
        selectedAppFilter = nil
        selectedDomainFilter = nil
        engine.applyFilters(searchText: "", contentFilter: .all, appFilter: nil, domainFilter: nil, dimension: selectedDimension)
    }
}

// MARK: - Sub-Enums and Models (Unchanged except moving from private to internal where needed)

enum StatisticsRange: String, CaseIterable, Identifiable, Sendable {
    case today, last7Days, last30Days, all
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
    func interval(containing now: Date, calendar: Calendar) -> DateInterval? {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today: return DateInterval(start: startOfToday, end: calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now)
        case .last7Days: return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? now, end: calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now)
        case .last30Days: return DateInterval(start: calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? now, end: calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now)
        case .all: return nil
        }
    }
    func fetchDescriptor(calendar: Calendar) -> FetchDescriptor<ActivityLog> {
        let sortBy = [SortDescriptor(\ActivityLog.startTime, order: .reverse)]
        guard let interval = interval(containing: Date(), calendar: calendar) else { return FetchDescriptor<ActivityLog>(sortBy: sortBy) }
        let start = interval.start
        let end = interval.end
        return FetchDescriptor<ActivityLog>(predicate: #Predicate { log in log.startTime >= start && log.startTime < end }, sortBy: sortBy)
    }
}

enum ContentFilter: String, CaseIterable, Identifiable, Sendable {
    case all, website, pdf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .website: return "网站"
        case .pdf: return "PDF"
        }
    }
}

enum RankingDimension: String, CaseIterable, Identifiable, Sendable {
    case app, domain, item
    var id: String { rawValue }
    var title: String {
        switch self {
        case .app: return "应用"
        case .domain: return "网站"
        case .item: return "具体条目"
        }
    }
}

enum DetailCategory: Sendable { case app, domain, pdf }

struct DaySummary: Identifiable, Sendable {
    let date: Date
    let totalTime: TimeInterval
    var id: Date { date }
}

struct RankingEntry: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval
    var id: String { name }
}

struct FilterOption: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval
    var id: String { name }
}

struct GroupedSummary: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval
    let details: [SummaryDetail]
    var id: String { name }
}

struct SummaryDetail: Identifiable, Sendable {
    let name: String
    let subtitle: String?
    let totalTime: TimeInterval
    var id: String { "\(name)|\(subtitle ?? "")" }
}

struct AppDurationSummary: Sendable {
    let displayName: String
    let totalTime: TimeInterval
}

struct FilterCriteria: Sendable {
    let normalizedSearchText: String
    let selectedContentFilter: ContentFilter
    let selectedAppFilter: String?
    let selectedDomainFilter: String?
}

struct FilterComputationResult: Sendable {
    let filteredLogs: [PreparedLog]
    let daySummaries: [DaySummary]
    let rangeTotalDuration: TimeInterval
    let topAppSummary: AppDurationSummary?
    let rankingEntries: [RankingEntry]
    let resolvedSelectedDay: Date?
    let todayDuration: TimeInterval
    let selectedDayAppSummaries: [GroupedSummary]
    let selectedDayDomainSummaries: [GroupedSummary]
    let selectedDayPdfSummaries: [GroupedSummary]
}

struct WhitelistSnapshot: Sendable {
    let lowercasedApps: [String]
    let domains: [String]
    let domainKeywords: [(domain: String, keyword: String)]
    init(whitelist: WhitelistManager) {
        self.lowercasedApps = whitelist.whitelistedApps.map { $0.lowercased() }
        self.domains = whitelist.whitelistedDomains
        self.domainKeywords = whitelist.whitelistedDomains.map { domain in
            let keyword = domain.components(separatedBy: ".").first?.lowercased() ?? domain.lowercased()
            return (domain: domain, keyword: keyword)
        }
    }
}

struct PreparedLog: Identifiable, Sendable {
    let identity: PreparedLogIdentity
    let appName: String
    let windowTitle: String
    let startTime: Date
    let dayStart: Date
    let duration: TimeInterval
    let resolvedDomain: String?
    let bilibiliIdentifier: String?
    let fullUrl: String?
    let searchableText: String
    let isPDF: Bool
    let isWebsite: Bool
    var id: PreparedLogIdentity { identity }
    init?(log: ActivityLog, whitelist: WhitelistSnapshot, calendar: Calendar) {
        if log.windowTitle.contains("权限") || log.windowTitle.contains("未知") || log.appName.isEmpty { return nil }
        let lowercasedAppName = log.appName.lowercased()
        let isWebsite = lowercasedAppName.contains("safari") || lowercasedAppName.contains("chrome") || lowercasedAppName.contains("edge")
        let isWhitelistedApp = whitelist.lowercasedApps.contains { $0 == lowercasedAppName || $0.contains(lowercasedAppName) || lowercasedAppName.contains($0) }
        guard isWhitelistedApp else { return nil }
        let resolvedDomain = Self.resolveDomain(for: log, whitelist: whitelist)
        if isWebsite && !log.windowTitle.contains("网页加载中") && resolvedDomain == nil { return nil }
        self.identity = PreparedLogIdentity(appName: log.appName, windowTitle: log.windowTitle, startTime: log.startTime, duration: log.duration, domain: log.domain, bilibiliIdentifier: log.bilibiliIdentifier, fullUrl: log.fullUrl)
        self.appName = log.appName
        self.windowTitle = log.windowTitle
        self.startTime = log.startTime
        self.dayStart = calendar.startOfDay(for: log.startTime)
        self.duration = log.duration
        self.resolvedDomain = resolvedDomain
        self.bilibiliIdentifier = log.bilibiliIdentifier
        self.fullUrl = log.fullUrl
        self.searchableText = [log.appName, log.windowTitle, resolvedDomain ?? "", log.fullUrl ?? ""].joined(separator: "\n").lowercased()
        let lowercasedTitle = log.windowTitle.lowercased()
        self.isPDF = (lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview")) && lowercasedTitle.contains(".pdf")
        self.isWebsite = isWebsite
    }
    private static func resolveDomain(for log: ActivityLog, whitelist: WhitelistSnapshot) -> String? {
        if let domain = log.domain, whitelist.domains.contains(domain) { return domain }
        let lowercasedWindowTitle = log.windowTitle.lowercased()
        return whitelist.domainKeywords.first { entry in lowercasedWindowTitle.contains(entry.keyword) || (entry.keyword == "bilibili" && lowercasedWindowTitle.contains("哔哩哔哩")) }?.domain
    }
}

struct PreparedLogIdentity: Hashable, Sendable {
    let appName: String
    let windowTitle: String
    let startTime: Date
    let duration: TimeInterval
    let domain: String?
    let bilibiliIdentifier: String?
    let fullUrl: String?
}

// Sub-Views remain largely the same, but I'll omit them here for brevity if they are identical.
// I'll include the ones that were in the original StatisticsView.swift to ensure full functionality.

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

private struct FilterSection: View {
    @Binding var searchText: String
    @Binding var selectedContentFilter: ContentFilter
    @Binding var selectedAppFilter: String?
    @Binding var selectedDomainFilter: String?
    let appOptions: [FilterOption]
    let domainOptions: [FilterOption]
    let formatDuration: (TimeInterval) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("筛选")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if hasActiveFilters {
                    Button("清空筛选") {
                        searchText = ""
                        selectedContentFilter = .all
                        selectedAppFilter = nil
                        selectedDomainFilter = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            TextField("搜索应用、域名、标题或链接", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("内容类型", selection: $selectedContentFilter) {
                ForEach(ContentFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Menu {
                    Button("全部应用") { selectedAppFilter = nil }
                    if !appOptions.isEmpty { Divider() }
                    ForEach(appOptions.prefix(12)) { option in
                        Button { selectedAppFilter = option.name } label: {
                            HStack {
                                Text(option.name)
                                Spacer()
                                Text(formatDuration(option.totalTime))
                            }
                        }
                    }
                } label: {
                    FilterChip(title: "应用", value: selectedAppFilter ?? "全部应用")
                }
                .buttonStyle(.plain)

                Menu {
                    Button("全部域名") { selectedDomainFilter = nil }
                    if !domainOptions.isEmpty { Divider() }
                    ForEach(domainOptions.prefix(12)) { option in
                        Button { selectedDomainFilter = option.name } label: {
                            HStack {
                                Text(option.name)
                                Spacer()
                                Text(formatDuration(option.totalTime))
                            }
                        }
                    }
                } label: {
                    FilterChip(title: "域名", value: selectedDomainFilter ?? "全部域名")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(20)
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedContentFilter != .all || selectedAppFilter != nil || selectedDomainFilter != nil
    }
}

private struct FilterChip: View {
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
        }
        .padding(.vertical, 10).padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.6)))
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
            Text("每日时长").font(.system(size: 18, weight: .semibold))
            Chart(daySummaries) { daySummary in
                BarMark(x: .value("日期", daySummary.date, unit: .day), y: .value("时长", daySummary.totalTime / 3600))
                .foregroundStyle(isHighlighted(daySummary.date) ? Color.accentColor : Color.accentColor.opacity(0.35))
                .cornerRadius(5)
                .annotation(position: .top, alignment: .center) {
                    if isHighlighted(daySummary.date) {
                        Text(formatDuration(daySummary.totalTime)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 220).chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { AxisMarks(values: .automatic) { value in AxisGridLine(); AxisValueLabel { if let date = value.as(Date.self) { Text(date.formatted(.dateTime.month(.defaultDigits).day())) } } } }
            .chartOverlay { proxy in GeometryReader { geometry in Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in updateSelection(at: value.location, proxy: proxy, geometry: geometry) }) } }

            if let strongestDay = daySummaries.max(by: { $0.totalTime < $1.totalTime }) {
                HStack {
                    Text("最高值").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(strongestDay.date.formatted(.dateTime.month(.defaultDigits).day())).font(.caption).foregroundColor(.secondary)
                    Text(formatDuration(strongestDay.totalTime)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }
        }
        .padding(18).background(Color.primary.opacity(0.04)).cornerRadius(20)
        .onAppear { highlightedDay = selectedDay }
        .onChange(of: selectedDay) { _, newValue in commitTask?.cancel(); if !isSameDay(highlightedDay, newValue) { highlightedDay = newValue } }
    }

    private func isHighlighted(_ date: Date) -> Bool { guard let highlightedDay else { return false }; return Calendar.current.isDate(date, inSameDayAs: highlightedDay) }
    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame.map({ geometry[$0] }) else { return }
        let relativeX = location.x - plotFrame.origin.x
        guard relativeX >= 0, relativeX <= plotFrame.size.width else { return }
        let nearest = daySummaries.compactMap { daySummary -> (summary: DaySummary, distance: CGFloat)? in
            guard let centerDate = Calendar.current.date(byAdding: .hour, value: 12, to: daySummary.date), let positionX = proxy.position(forX: centerDate) else { return nil }
            return (daySummary, abs(positionX - relativeX))
        }.min { $0.distance < $1.distance }
        if let nearest, !isHighlighted(nearest.summary.date) { highlightedDay = nearest.summary.date; scheduleCommit(for: nearest.summary.date) }
    }
    private func scheduleCommit(for date: Date) { commitTask?.cancel(); commitTask = Task { try? await Task.sleep(for: .milliseconds(80)); guard !Task.isCancelled else { return }; await MainActor.run { onSelectDay(date) } } }
    private func isSameDay(_ lhs: Date?, _ rhs: Date?) -> Bool { switch (lhs, rhs) { case let (left?, right?): return Calendar.current.isDate(left, inSameDayAs: right); case (nil, nil): return true; default: return false } }
}

private struct DayPickerSection: View {
    let daySummaries: [DaySummary]
    let selectedDay: Date?
    let onSelect: (Date) -> Void
    let formatDuration: (TimeInterval) -> String
    let formatDate: (Date) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日期").font(.system(size: 18, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(daySummaries.sorted { $0.date > $1.date }) { daySummary in
                        Button(action: { onSelect(daySummary.date) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(formatDate(daySummary.date)).font(.system(size: 13, weight: .semibold))
                                Text(formatDuration(daySummary.totalTime)).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(isSelected(daySummary.date) ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private func isSelected(_ date: Date) -> Bool { guard let selectedDay else { return false }; return Calendar.current.isDate(date, inSameDayAs: selectedDay) }
}

private struct RankingSection: View {
    @Binding var selectedDimension: RankingDimension
    let rankingEntries: [RankingEntry]
    let formatDuration: (TimeInterval) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("使用时间总排行").font(.system(size: 18, weight: .semibold))
            Picker("排行维度", selection: $selectedDimension) { ForEach(RankingDimension.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if rankingEntries.isEmpty { Text("无数据").font(.caption).foregroundColor(.secondary).padding(.top, 4) } else {
                VStack(spacing: 10) {
                    ForEach(Array(rankingEntries.prefix(8).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.system(size: 12, weight: .bold, design: .monospaced)).frame(width: 24, height: 24).background(Circle().fill(Color.accentColor.opacity(0.14)))
                            Text(entry.name).lineLimit(1); Spacer()
                            Text(formatDuration(entry.totalTime)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }
        }.padding(18).background(Color.primary.opacity(0.04)).cornerRadius(20)
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
                VStack(alignment: .leading, spacing: 4) { Text("当日明细").font(.system(size: 18, weight: .semibold)); Text(selectedDay.map(formatDate) ?? "暂无日期").font(.caption).foregroundColor(.secondary) }; Spacer()
            }
            if appSummaries.isEmpty && domainSummaries.isEmpty && pdfSummaries.isEmpty { Text("无记录").font(.caption).foregroundColor(.secondary) } else {
                VStack(spacing: 12) {
                    CategorySummaryGroup(title: "应用", emptyText: "无应用记录", summaries: appSummaries, formatDuration: formatDuration, onDelete: { onDelete(.app, $0, $1) })
                    CategorySummaryGroup(title: "域名", emptyText: "无域名记录", summaries: domainSummaries, formatDuration: formatDuration, onDelete: { onDelete(.domain, $0, $1) })
                    CategorySummaryGroup(title: "PDF", emptyText: "无 PDF 记录", summaries: pdfSummaries, formatDuration: formatDuration, onDelete: { onDelete(.pdf, $0, $1) })
                }
            }
        }.padding(18).background(Color.primary.opacity(0.04)).cornerRadius(20)
    }
}

private struct CategorySummaryGroup: View {
    let title, emptyText: String; let summaries: [GroupedSummary]; let formatDuration: (TimeInterval) -> String; let onDelete: (String, String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if summaries.isEmpty { Text(emptyText).font(.caption).foregroundColor(.secondary) } else {
                ForEach(summaries) { summary in SummaryEntryCardView(summary: summary, formatDuration: formatDuration, onDelete: { onDelete(summary.name, $0) }) }
            }
        }
    }
}

private struct SummaryEntryCardView: View {
    let summary: GroupedSummary; let formatDuration: (TimeInterval) -> String; let onDelete: (String) -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            ZStack { RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)).frame(width: 36, height: 36); Text(String(summary.name.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)).foregroundColor(.accentColor) }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(summary.name).font(.system(size: 15, weight: .semibold)).lineLimit(1); Spacer(); Text(formatDuration(summary.totalTime)).font(.system(size: 13, design: .monospaced)).foregroundColor(.secondary) }
                ForEach(summary.details) { detail in
                    HStack(alignment: .top) {
                        Text("•").foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) { Text(detail.name).font(.system(size: 12)).foregroundColor(.primary.opacity(0.76)).lineLimit(2); if let subtitle = detail.subtitle { Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1) } }
                        Spacer(); Text(formatDuration(detail.totalTime)).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary.opacity(0.85))
                    }.contextMenu { Button(role: .destructive) { onDelete(detail.name) } label: { Label("删除记录", systemImage: "trash") } }
                }
            }
        }.padding(15).background(Color.white.opacity(0.5)).cornerRadius(16)
    }
}

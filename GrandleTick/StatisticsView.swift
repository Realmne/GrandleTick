import SwiftUI
import SwiftData
import Charts

// MARK: - Main Statistics View

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var engine = StatisticsEngine()
    @State private var whitelist = WhitelistManager.shared
    @State private var selectedRange: StatisticsRange = .week
    @State private var selectedDimension: RankingDimension = .app
    @State private var searchText: String = ""
    @State private var selectedContentFilter: ContentFilter = .all
    @State private var selectedAppFilter: String?
    @State private var selectedDomainFilter: String?
    @State private var searchDebounceTask: Task<Void, Never>?

    private let calendar = Calendar.current

    var body: some View {
        let hasBaseRangeData = !engine.baseRangeLogs.isEmpty

        ZStack {
            // 1. 采用类似报告的精美温暖渐变背景色。
            backgroundGradient

            VStack(spacing: 0) {
                // 2. 顶部浮动毛玻璃控制栏，包含时间范围选项与翻页逻辑。
                headerSection(totalDuration: engine.rangeTotalDuration)

                if !hasBaseRangeData {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // 3. 统计核心卡片组，提供总时长、活跃天数等核心指标。
                            overviewCardsGrid

                            // 4. 双环形占比图，并排展示 [专注 vs 娱乐] 和 [内容载体分布]。
                            HStack(spacing: 16) {
                                LearningVsEntertainmentDonutCard(
                                    studyDuration: engine.studyDuration,
                                    entertainmentDuration: engine.entertainmentDuration,
                                    formatDuration: formatCompactDuration
                                )

                                ContentCategoryDonutCard(
                                    websiteDuration: engine.websiteDuration,
                                    pdfDuration: engine.pdfDuration,
                                    totalDuration: engine.studyDuration,
                                    formatDuration: formatCompactDuration
                                )
                            }

                            // 5. 每日趋势图（交互式柱状图，支持用户拖拽或点击单天）。
                            RangeTrendSection(
                                daySummaries: engine.daySummaries,
                                selectedDay: engine.selectedDay,
                                onSelectDay: { engine.updateSelectedDay($0) },
                                formatDuration: formatCompactDuration
                            )

                            // 6. 24 小时节奏段，包含时段面积图与作息最早最晚时间卡片。
                            RhythmSection(
                                hourlyDurations: engine.hourlyDurations,
                                primaryTimeSlot: engine.primaryTimeSlot,
                                earliestStudyStart: engine.earliestStudyStart,
                                latestStudyEnd: engine.latestStudyEnd,
                                formatDuration: formatCompactDuration,
                                formatClock: formatClock
                            )

                            // 7. App 专注度分布，提供 App 占比环形图及热门前三排行。
                            AppFocusDonutCard(
                                topApps: engine.rankingEntries,
                                totalDuration: engine.studyDuration,
                                formatDuration: formatCompactDuration
                            )

                            // 8. 热门网站与热门 PDF 分布（并排列表排行）。
                            HStack(spacing: 16) {
                                ReportRankingPanel(
                                    title: "热门网站 (前三)",
                                    items: engine.topWebsites,
                                    formatDuration: formatCompactDuration
                                )

                                ReportRankingPanel(
                                    title: "热门 PDF (前三)",
                                    items: engine.topPDFs,
                                    formatDuration: formatCompactDuration
                                )
                            }

                            // 9. 自定义筛选器区域，用户可自行搜索、过滤载体和指定域名。
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
                                // 10. 日期滚动点选器。
                                DayPickerSection(
                                    daySummaries: engine.daySummaries,
                                    selectedDay: engine.selectedDay,
                                    onSelect: { engine.updateSelectedDay($0) },
                                    formatDuration: formatCompactDuration,
                                    formatDate: formatShortDate
                                )

                                // 11. 当日详情列表（包含右键菜单删除功能）。
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

                                // 12. 全周期大排行榜（前八名，支持维度切换）。
                                RankingSection(
                                    selectedDimension: $selectedDimension,
                                    rankingEntries: engine.rankingEntries,
                                    formatDuration: formatCompactDuration
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
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
        .onChange(of: selectedContentFilter) { _, _ in refreshFiltersOnly() }
        .onChange(of: selectedAppFilter) { _, _ in refreshFiltersOnly() }
        .onChange(of: selectedDomainFilter) { _, _ in refreshFiltersOnly() }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
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
    }

    @ViewBuilder
    private func headerSection(totalDuration: TimeInterval) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("数据中心")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary.opacity(0.88))
                    Text("所有专注和活动统计回顾")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 上一期/下一期翻页控制（仅在本周、本月、本年模式下显式启用）
                if selectedRange != .all {
                    HStack(spacing: 12) {
                        ReportPagerButton(
                            systemImage: "chevron.left",
                            isDisabled: !engine.canShowPreviousPeriod,
                            action: { shiftReferencePeriod(by: -1) }
                        )

                        Text(formatDateRange(for: selectedRange, referenceDate: engine.referenceDate))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 100, alignment: .center)

                        ReportPagerButton(
                            systemImage: "chevron.right",
                            isDisabled: !engine.canShowNextPeriod,
                            action: { shiftReferencePeriod(by: 1) }
                        )
                    }
                } else {
                    Text("历史全部数据")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .padding(.bottom, 14)
        .background(Material.regular)
        .overlay(Divider(), alignment: .bottom)
    }

    @ViewBuilder
    private var overviewCardsGrid: some View {
        // 布局设计：3列 x 2行
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            OverviewCard(
                title: "总学习时长",
                value: formatDetailedDuration(engine.studyDuration),
                subtitle: selectedRange.title,
                tint: .blue
            )

            OverviewCard(
                title: "今日学习时长",
                value: formatCompactDuration(engine.todayDuration),
                subtitle: "今天",
                tint: .orange
            )

            OverviewCard(
                title: "活跃天数",
                value: "\(engine.activeDays) 天",
                subtitle: "累计活跃天数",
                tint: .green
            )

            OverviewCard(
                title: "日均学习时长",
                value: formatCompactDuration(engine.averageDailyDuration),
                subtitle: "单日均值",
                tint: .indigo
            )

            OverviewCard(
                title: "最长连续天数",
                value: "\(engine.longestStreak) 天",
                subtitle: "连续专注记录",
                tint: .purple
            )

            OverviewCard(
                title: "同比变化",
                value: formatComparisonValue(engine.comparison),
                subtitle: formatComparisonSubtitle(engine.comparison, range: selectedRange),
                tint: .pink
            )
        }
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
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: - Logic Helpers

    private func refreshRangeData() {
        engine.refreshBaseData(for: selectedRange, modelContext: modelContext, whitelist: whitelist)
        sanitizeFilterSelection()
        refreshFiltersOnly()
    }

    private func refreshFiltersOnly() {
        engine.applyFilters(
            searchText: searchText,
            contentFilter: selectedContentFilter,
            appFilter: selectedAppFilter,
            domainFilter: selectedDomainFilter,
            dimension: selectedDimension,
            range: selectedRange
        )
    }

    private func shiftReferencePeriod(by val: Int) {
        engine.shiftReferenceDate(by: val, range: selectedRange)
        refreshRangeData()
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

    private func clearFilters() {
        searchDebounceTask?.cancel()
        searchText = ""
        selectedContentFilter = .all
        selectedAppFilter = nil
        selectedDomainFilter = nil
        refreshFiltersOnly()
    }

    private func scheduleSearchRefresh() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                refreshFiltersOnly()
            }
        }
    }

    private func deleteLogs(on selectedDay: Date?, category: DetailCategory, summaryName: String, detailName: String) {
        guard let selectedDay else { return }

        // 1. 按照当前选中日期以及特定应用/域名定位需清理的日志标识。
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

        // 2. 从持久化上下文（ModelContext）中逐个擦除匹配项并保存。
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

        // 3. 执行物理保存并刷新引擎数据。
        try? modelContext.save()
        refreshRangeData()
    }

    // MARK: - Formatters

    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分"
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
        let comps = calendar.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 0)/\(comps.day ?? 0)"
    }

    private func formatLongDate(_ date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)年\(comps.month ?? 0)月\(comps.day ?? 0)日"
    }

    private func formatDateRange(for range: StatisticsRange, referenceDate: Date) -> String {
        let now = Date()
        guard let interval = engine.interval(for: range, referenceDate: referenceDate, currentDate: now) else {
            return "全部历史"
        }
        let endDate = interval.end.addingTimeInterval(-1)

        let startComps = calendar.dateComponents([.year, .month, .day], from: interval.start)
        let endComps = calendar.dateComponents([.year, .month, .day], from: endDate)

        if range == .today {
            return "\(startComps.year ?? 0)年\(startComps.month ?? 0)月\(startComps.day ?? 0)日"
        }

        return "\(startComps.month ?? 0)/\(startComps.day ?? 0) - \(endComps.month ?? 0)/\(endComps.day ?? 0)"
    }

    private func formatClock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func formatComparisonValue(_ comparison: ReportComparison?) -> String {
        guard let comparison else { return "第一期" }
        if let rate = comparison.totalDurationChangeRate {
            let pct = Int((rate * 100).rounded())
            if pct > 0 {
                return "+\(pct)%"
            } else if pct < 0 {
                return "\(pct)%"
            } else {
                return "持平"
            }
        }
        return "第一期"
    }

    private func formatComparisonSubtitle(_ comparison: ReportComparison?, range: StatisticsRange) -> String {
        guard let comparison else { return "期待后续统计" }
        let delta = comparison.totalDurationDelta
        let direction = delta > 0 ? "多" : "少"
        if delta == 0 {
            return "较\(range.previousTitle)持平"
        }
        return "较\(range.previousTitle)\(direction) \(formatCompactDuration(abs(delta)))"
    }
}

// MARK: - Supporting Subviews & Components

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
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("高级数据筛选")
                    .font(.system(size: 15, weight: .semibold))
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
                    .font(.caption)
                }
            }

            TextField("搜索应用、域名、标题或链接", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("内容类型", selection: $selectedContentFilter) {
                ForEach(ContentFilter.allCases) { filter in
                    Text(filter == .all ? "全部" : filter == .website ? "网页" : "PDF").tag(filter)
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
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.5), lineWidth: 1))
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
            Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary)
        }
        .padding(.vertical, 8).padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
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
            Text("每日专注趋势").font(.headline)
            Chart(daySummaries) { daySummary in
                BarMark(x: .value("日期", daySummary.date, unit: .day), y: .value("时长", daySummary.totalTime / 3600))
                .foregroundStyle(isHighlighted(daySummary.date) ? Color.blue.opacity(0.8) : Color.blue.opacity(0.3))
                .cornerRadius(5)
                .annotation(position: .top, alignment: .center) {
                    if isHighlighted(daySummary.date) {
                        Text(formatDuration(daySummary.totalTime)).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 200).chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { AxisMarks(values: .automatic) { value in AxisGridLine(); AxisValueLabel { if let date = value.as(Date.self) { Text(formatShortDate(date)) } } } }
            .chartOverlay { proxy in GeometryReader { geometry in Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in updateSelection(at: value.location, proxy: proxy, geometry: geometry) }) } }

            if let strongestDay = daySummaries.max(by: { $0.totalTime < $1.totalTime }) {
                HStack {
                    Text("最高单日专注").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(strongestDay.date.formatted(.dateTime.month(.defaultDigits).day())).font(.caption).foregroundColor(.secondary)
                    Text(formatDuration(strongestDay.totalTime)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.72), lineWidth: 1))
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
    private func formatShortDate(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 0)/\(comps.day ?? 0)"
    }
}

private struct DayPickerSection: View {
    let daySummaries: [DaySummary]
    let selectedDay: Date?
    let onSelect: (Date) -> Void
    let formatDuration: (TimeInterval) -> String
    let formatDate: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("日期快速跳转").font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(daySummaries.sorted { $0.date > $1.date }) { daySummary in
                        Button(action: { onSelect(daySummary.date) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatDate(daySummary.date)).font(.system(size: 12, weight: .semibold))
                                Text(formatDuration(daySummary.totalTime)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected(daySummary.date) ? Color.blue.opacity(0.18) : Color.white.opacity(0.6)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected(daySummary.date) ? Color.blue.opacity(0.3) : Color.black.opacity(0.04), lineWidth: 1))
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
            Text("专注总排行榜").font(.headline)
            Picker("排行维度", selection: $selectedDimension) {
                Text("应用").tag(RankingDimension.app)
                Text("域名").tag(RankingDimension.domain)
                Text("窗口").tag(RankingDimension.item)
            }
            .pickerStyle(.segmented)

            if rankingEntries.isEmpty {
                Text("无数据").font(.caption).foregroundColor(.secondary).padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(rankingEntries.prefix(8).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.blue.opacity(0.12)))

                            Text(entry.name)
                                .font(.system(size: 13))
                                .lineLimit(1)

                            Spacer()

                            Text(formatDuration(entry.totalTime))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                        if index < min(rankingEntries.count, 8) - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

enum DetailCategory: Sendable { case app, domain, pdf }

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
                    Text("选中日期活动明细").font(.headline)
                    Text(selectedDay.map(formatDate) ?? "暂无日期").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }

            if appSummaries.isEmpty && domainSummaries.isEmpty && pdfSummaries.isEmpty {
                Text("该日无专注记录").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 16)
            } else {
                VStack(spacing: 12) {
                    CategorySummaryGroup(title: "应用维度", emptyText: "无应用记录", summaries: appSummaries, formatDuration: formatDuration, onDelete: { onDelete(.app, $0, $1) })
                    CategorySummaryGroup(title: "域名维度", emptyText: "无域名记录", summaries: domainSummaries, formatDuration: formatDuration, onDelete: { onDelete(.domain, $0, $1) })
                    CategorySummaryGroup(title: "PDF 维度", emptyText: "无 PDF 记录", summaries: pdfSummaries, formatDuration: formatDuration, onDelete: { onDelete(.pdf, $0, $1) })
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

private struct CategorySummaryGroup: View {
    let title, emptyText: String
    let summaries: [GroupedSummary]
    let formatDuration: (TimeInterval) -> String
    let onDelete: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
            if summaries.isEmpty {
                Text(emptyText).font(.caption).foregroundColor(.secondary).padding(.leading, 8)
            } else {
                ForEach(summaries) { summary in
                    SummaryEntryCardView(summary: summary, formatDuration: formatDuration, onDelete: { onDelete(summary.name, $0) })
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
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.12)).frame(width: 32, height: 32)
                Text(String(summary.name.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(summary.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(formatDuration(summary.totalTime)).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                }

                ForEach(summary.details) { detail in
                    HStack(alignment: .top) {
                        Text("•").foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(detail.name).font(.system(size: 11)).foregroundColor(.primary.opacity(0.8)).lineLimit(2)
                            if let subtitle = detail.subtitle {
                                Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(formatDuration(detail.totalTime)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary.opacity(0.8))
                    }
                    .contextMenu {
                        Button(role: .destructive) { onDelete(detail.name) } label: {
                            Label("删除本条记录", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.5))
        .cornerRadius(14)
    }
}

// MARK: - Merged Custom Report Components

private struct LearningVsEntertainmentDonutCard: View {
    let studyDuration: TimeInterval
    let entertainmentDuration: TimeInterval
    let formatDuration: (TimeInterval) -> String

    @State private var animateData = false

    private var total: TimeInterval { studyDuration + entertainmentDuration }
    private var studyShare: Double { total > 0 ? studyDuration / total : 1.0 }

    struct Segment: Identifiable {
        let id = UUID()
        let type: String
        let duration: Double
        let color: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("专注与娱乐分布")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 16) {
                let data = [
                    Segment(type: "学习时间", duration: studyDuration, color: Color.blue.opacity(0.65)),
                    Segment(type: "娱乐时间", duration: entertainmentDuration, color: Color.orange.opacity(0.55))
                ].filter { $0.duration > 0 }

                Chart(data) { segment in
                    SectorMark(
                        angle: .value("时间", segment.duration),
                        innerRadius: .ratio(0.60),
                        angularInset: 2.0
                    )
                    .cornerRadius(6)
                    .foregroundStyle(segment.color)
                }
                .frame(width: 100, height: 100)
                .scaleEffect(animateData ? 1.0 : 0.88)
                .opacity(animateData ? 1.0 : 0.0)
                .chartBackground { chartProxy in
                    GeometryReader { geo in
                        if let frame = chartProxy.plotFrame {
                            let frameWidth = geo[frame].width
                            let frameHeight = geo[frame].height
                            VStack(spacing: 2) {
                                Text("学习占比")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                Text("\(Int((studyShare * 100).rounded()))%")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.blue.opacity(0.85))
                            }
                            .position(x: frameWidth / 2, y: frameHeight / 2)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ReportLegendStat(title: "学习专注", value: formatDuration(studyDuration), tint: Color.blue.opacity(0.65))
                    ReportLegendStat(title: "娱乐消遣", value: formatDuration(entertainmentDuration), tint: Color.orange.opacity(0.55))
                }

                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.80).delay(0.15)) {
                animateData = true
            }
        }
    }
}

private struct ContentCategoryDonutCard: View {
    let websiteDuration: TimeInterval
    let pdfDuration: TimeInterval
    let totalDuration: TimeInterval
    let formatDuration: (TimeInterval) -> String

    @State private var animateData = false

    struct Category: Identifiable {
        let id = UUID()
        let name: String
        let duration: Double
        let color: Color
    }

    private var categories: [Category] {
        let appDuration = max(0, totalDuration - websiteDuration - pdfDuration)
        return [
            Category(name: "PDF 文档", duration: pdfDuration, color: Color.purple.opacity(0.55)),
            Category(name: "网页浏览", duration: websiteDuration, color: Color.teal.opacity(0.55)),
            Category(name: "原生应用", duration: appDuration, color: Color.blue.opacity(0.65))
        ].filter { $0.duration > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("学习载体分布")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 16) {
                Chart(categories) { item in
                    SectorMark(
                        angle: .value("时长", item.duration),
                        innerRadius: .ratio(0.60),
                        angularInset: 2.0
                    )
                    .cornerRadius(5)
                    .foregroundStyle(item.color)
                }
                .frame(width: 100, height: 100)
                .scaleEffect(animateData ? 1.0 : 0.88)
                .opacity(animateData ? 1.0 : 0.0)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(categories) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name)
                                    .font(.system(size: 9))
                                    .foregroundColor(.primary.opacity(0.85))
                                Text(formatDuration(item.duration))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.80).delay(0.15)) {
                animateData = true
            }
        }
    }
}

private struct RhythmSection: View {
    let hourlyDurations: [Double]
    let primaryTimeSlot: ReportTimeSlot?
    let earliestStudyStart: Date?
    let latestStudyEnd: Date?
    let formatDuration: (TimeInterval) -> String
    let formatClock: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("专注节奏分布")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                // Left: Hourly Area/Line Chart
                VStack(alignment: .leading, spacing: 10) {
                    ReportRhythmHourlyChart(hourlyDurations: hourlyDurations)

                    if let primaryTimeSlot {
                        Text("您更常在")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary) +
                        Text(" \(primaryTimeSlot.title) ")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.purple) +
                        Text("时段进入高效状态。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                // Right: Clock indicator cards
                VStack(spacing: 12) {
                    ClockCard(
                        title: "最早开始",
                        time: earliestStudyStart.map(formatClock) ?? "--:--",
                        subtitle: "开启高效时刻"
                    )

                    ClockCard(
                        title: "最晚结束",
                        time: latestStudyEnd.map(formatClock) ?? "--:--",
                        subtitle: "结束一天专注"
                    )
                }
                .frame(width: 160)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

private struct ReportRhythmHourlyChart: View {
    let hourlyDurations: [Double]

    @State private var animateData = false

    var body: some View {
        let chartData = hourlyDurations.enumerated().map { index, value in
            (hour: index, value: animateData ? (value / 3600.0) : 0.0)
        }

        Chart {
            ForEach(chartData, id: \.hour) { item in
                AreaMark(
                    x: .value("时间", "\(item.hour)点"),
                    y: .value("时长", item.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.22), Color.purple.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(chartData, id: \.hour) { item in
                LineMark(
                    x: .value("时间", "\(item.hour)点"),
                    y: .value("时长", item.value)
                )
                .foregroundStyle(Color.purple.opacity(0.60))
                .lineStyle(StrokeStyle(lineWidth: 2.0))
            }
        }
        .frame(height: 120)
        .chartXAxis {
            AxisMarks(values: ["0点", "4点", "8点", "12点", "16点", "20点"]) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label).font(.system(size: 9))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(hours == 0 ? "0h" : String(format: "%.1fh", hours)).font(.system(size: 9))
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.80).delay(0.2)) {
                animateData = true
            }
        }
    }
}

private struct ClockCard: View {
    let title: String
    let time: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(time)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.04), lineWidth: 1))
    }
}

private struct AppFocusDonutCard: View {
    let topApps: [RankingEntry]
    let totalDuration: TimeInterval
    let formatDuration: (TimeInterval) -> String

    @State private var animateData = false

    private let palette: [Color] = [
        Color.blue.opacity(0.65),
        Color.purple.opacity(0.55),
        Color.teal.opacity(0.55),
        Color.pink.opacity(0.55)
    ]

    struct Segment: Identifiable {
        let id = UUID()
        let name: String
        let duration: Double
        let color: Color
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var sumTop = 0.0

        for (index, item) in topApps.prefix(3).enumerated() {
            let color = palette[index % palette.count]
            result.append(Segment(name: item.name, duration: item.totalTime, color: color))
            sumTop += item.totalTime
        }

        let remaining = max(0, totalDuration - sumTop)
        if remaining > 60 {
            result.append(Segment(name: "其他应用", duration: remaining, color: Color.secondary.opacity(0.25)))
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("应用专注占比分布")
                .font(.headline)

            HStack(spacing: 20) {
                Chart(segments) { segment in
                    SectorMark(
                        angle: .value("时长", segment.duration),
                        innerRadius: .ratio(0.60),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(segment.color)
                }
                .frame(width: 100, height: 100)
                .scaleEffect(animateData ? 1.0 : 0.88)
                .opacity(animateData ? 1.0 : 0.0)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(segments) { segment in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(segment.color)
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(segment.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineLimit(1)
                                Text(formatDuration(segment.duration))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.80).delay(0.2)) {
                animateData = true
            }
        }
    }
}

private struct ReportRankingPanel: View {
    let title: String
    let items: [RankingEntry]
    let formatDuration: (TimeInterval) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))

            if items.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                let total = items.reduce(0) { $0 + $1.totalTime }
                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let share = total > 0 ? item.totalTime / total : 0.0
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(index + 1). \(item.name)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)

                                Spacer()

                                Text(formatDuration(item.totalTime))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 6)

                                    Capsule()
                                        .fill(Color.blue.opacity(0.6))
                                        .frame(width: max(geometry.size.width * CGFloat(share), 6), height: 6)
                                }
                            }
                            .frame(height: 6)

                            Text("占比 \(Int((share * 100).rounded()))%")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

private struct ReportLegendStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint.opacity(0.85))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(isDisabled ? 0.38 : 0.86))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isDisabled ? Color.white.opacity(0.34) : isPressed ? Color.white.opacity(0.96) : isHovered ? Color.white.opacity(0.90) : Color.white.opacity(0.72))
                )
                .overlay(
                    Circle()
                        .stroke(isDisabled ? Color.black.opacity(0.04) : Color.black.opacity(isHovered ? 0.10 : 0.07), lineWidth: 0.8)
                )
                .scaleEffect(isPressed && !isDisabled ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            if !isDisabled {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
        .pressing { pressing in
            if !isDisabled {
                withAnimation(.easeOut(duration: 0.08)) {
                    isPressed = pressing
                }
            }
        }
    }
}

private struct PressObserverStyle: ButtonStyle {
    let onPress: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, isPressed in
            onPress(isPressed)
        }
    }
}

extension View {
    fileprivate func pressing(_ onPress: @escaping (Bool) -> Void) -> some View {
        buttonStyle(PressObserverStyle(onPress: onPress))
    }
}

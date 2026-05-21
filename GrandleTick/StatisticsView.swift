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
    @State private var searchText: String = ""
    @State private var appliedSearchText: String = ""
    @State private var selectedContentFilter: ContentFilter = .all
    @State private var selectedAppFilter: String?
    @State private var selectedDomainFilter: String?
    @State private var baseRangeLogs: [PreparedLog] = []
    @State private var rangeLogs: [PreparedLog] = []
    @State private var daySummaries: [DaySummary] = []
    @State private var rankingEntriesCache: [RankingEntry] = []
    @State private var rangeTotalDuration: TimeInterval = 0
    @State private var todayDuration: TimeInterval = 0
    @State private var selectedDayAppSummaries: [GroupedSummary] = []
    @State private var selectedDayDomainSummaries: [GroupedSummary] = []
    @State private var selectedDayPdfSummaries: [GroupedSummary] = []
    @State private var topTopicSummary: TopicDurationSummary?
    @State private var appFilterOptions: [FilterOption] = []
    @State private var domainFilterOptions: [FilterOption] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var filterComputationTask: Task<Void, Never>?
    @State private var filterComputationToken: UInt = 0

    private let calendar = Calendar.current

    var body: some View {
        let effectiveSelectedDay = Self.resolvedSelectedDay(
            currentSelection: selectedDay,
            from: daySummaries,
            calendar: calendar
        )
        let hasBaseRangeData = !baseRangeLogs.isEmpty

        VStack(spacing: 0) {
            headerView(totalDuration: rangeTotalDuration)
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
                            appOptions: appFilterOptions,
                            domainOptions: domainFilterOptions,
                            formatDuration: formatCompactDuration
                        )

                        if rangeLogs.isEmpty {
                            filteredEmptyStateView
                        } else {
                            overviewCards(
                                totalDuration: rangeTotalDuration,
                                activeDays: daySummaries.count,
                                todayDuration: todayDuration,
                                topTopicSummary: topTopicSummary
                            )

                            RangeTrendSection(
                                daySummaries: daySummaries,
                                selectedDay: effectiveSelectedDay,
                                onSelectDay: updateSelectedDay,
                                formatDuration: formatCompactDuration
                            )

                            DayPickerSection(
                                daySummaries: daySummaries,
                                selectedDay: effectiveSelectedDay,
                                onSelect: updateSelectedDay,
                                formatDuration: formatCompactDuration,
                                formatDate: formatShortDate
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

                            RankingSection(
                                selectedDimension: $selectedDimension,
                                rankingEntries: rankingEntriesCache,
                                formatDuration: formatCompactDuration
                            )
                        }
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
        .onChange(of: searchText) { _, _ in scheduleSearchRefresh() }
        .onChange(of: appliedSearchText) { _, _ in refreshFilteredData() }
        .onChange(of: selectedContentFilter) { _, _ in refreshFilteredData() }
        .onChange(of: selectedAppFilter) { _, _ in refreshFilteredData() }
        .onChange(of: selectedDomainFilter) { _, _ in refreshFilteredData() }
        .onDisappear {
            searchDebounceTask?.cancel()
            filterComputationTask?.cancel()
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
        topTopicSummary: TopicDurationSummary?
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
                title: "单主题最高时长",
                value: topTopicSummary.map { formatCompactDuration($0.totalTime) } ?? "0分",
                subtitle: topTopicSummary?.displayName ?? "无数据",
                tint: .pink
            )
        }
    }

    nonisolated private static func dailySummaries(for logs: [PreparedLog]) -> [DaySummary] {
        let grouped = Dictionary(grouping: logs) { $0.dayStart }
        return grouped.map { date, dayLogs in
            DaySummary(date: date, totalTime: dayLogs.reduce(0) { $0 + $1.duration })
        }
        .sorted { $0.date < $1.date }
    }

    nonisolated private static func rankingEntries(for logs: [PreparedLog], dimension: RankingDimension) -> [RankingEntry] {
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

    nonisolated private static func groupedSummaries(for logs: [PreparedLog], dimension: RankingDimension) -> [GroupedSummary] {
        let grouped = Dictionary(grouping: logs) { log in
            rankingKey(for: log, dimension: dimension)
        }

        return grouped.compactMap { key, groupedLogs in
            guard let key else { return nil }

            if dimension == .domain {
                return GroupedSummary(
                    name: key,
                    totalTime: groupedLogs.reduce(0) { $0 + $1.duration },
                    details: [
                        SummaryDetail(
                            name: key,
                            subtitle: groupedLogs.first?.appName,
                            totalTime: groupedLogs.reduce(0) { $0 + $1.duration }
                        )
                    ]
                )
            }

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

    nonisolated private static func logs(for selectedDay: Date?, in logs: [PreparedLog], calendar: Calendar) -> [PreparedLog] {
        guard let selectedDay else { return [] }
        return logs.filter { calendar.isDate($0.startTime, inSameDayAs: selectedDay) }
    }

    nonisolated private static func rankingKey(for log: PreparedLog, dimension: RankingDimension) -> String? {
        switch dimension {
        case .app:
            return log.appName
        case .domain:
            return log.resolvedDomain
        case .item:
            return log.windowTitle
        }
    }

    nonisolated private static func detailKey(for log: PreparedLog, dimension: RankingDimension) -> String {
        switch dimension {
        case .app:
            return log.windowTitle
        case .domain:
            return log.resolvedDomain ?? log.appName
        case .item:
            return log.resolvedDomain ?? log.appName
        }
    }

    nonisolated private static func detailSubtitle(for logs: [PreparedLog], dimension: RankingDimension) -> String? {
        guard dimension == .item else { return nil }

        let sources = Set(logs.map { $0.resolvedDomain ?? $0.appName }).sorted()
        guard !sources.isEmpty else { return nil }
        return sources.joined(separator: " · ")
    }

    nonisolated private static func pdfSummaries(for logs: [PreparedLog]) -> [GroupedSummary] {
        let pdfLogs = logs.filter(\.isPDF)
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

    nonisolated private static func resolvedSelectedDay(
        currentSelection: Date?,
        from daySummaries: [DaySummary],
        calendar: Calendar
    ) -> Date? {
        guard !daySummaries.isEmpty else { return nil }

        if let currentSelection,
           daySummaries.contains(where: { calendar.isDate($0.date, inSameDayAs: currentSelection) }) {
            return currentSelection
        }

        return daySummaries.last?.date
    }

    private func refreshRangeData() {
        searchDebounceTask?.cancel()
        filterComputationTask?.cancel()

        let whitelistSnapshot = WhitelistSnapshot(whitelist: whitelist)
        let newRangeLogs = allLogs.compactMap { log in
            PreparedLog(log: log, whitelist: whitelistSnapshot, calendar: calendar)
        }
        .filter { selectedRange.contains($0.startTime, calendar: calendar) }

        baseRangeLogs = newRangeLogs
        appFilterOptions = buildFilterOptions(from: newRangeLogs, dimension: .app)
        domainFilterOptions = buildFilterOptions(from: newRangeLogs, dimension: .domain)
        sanitizeFilterSelection()
        appliedSearchText = normalizedSearchText(from: searchText)
        refreshFilteredData()
    }

    private func refreshFilteredData() {
        filterComputationTask?.cancel()
        filterComputationToken &+= 1

        let token = filterComputationToken
        let sourceLogs = baseRangeLogs
        let filters = activeFilters()
        let selectedDimension = selectedDimension
        let currentSelectedDay = selectedDay
        let calendar = calendar

        filterComputationTask = Task.detached(priority: .userInitiated) {
            let newFilteredLogs = Self.filteredLogs(from: sourceLogs, using: filters)
            let newDaySummaries = Self.dailySummaries(for: newFilteredLogs)
            let resolvedDay = Self.resolvedSelectedDay(
                currentSelection: currentSelectedDay,
                from: newDaySummaries,
                calendar: calendar
            )
            let todayLogs = Self.logs(for: Date(), in: newFilteredLogs, calendar: calendar)
            let selectedLogs = Self.logs(for: resolvedDay, in: newFilteredLogs, calendar: calendar)
            let result = FilterComputationResult(
                filteredLogs: newFilteredLogs,
                daySummaries: newDaySummaries,
                rangeTotalDuration: newFilteredLogs.reduce(0) { $0 + $1.duration },
                topTopicSummary: Self.topTopicSummary(in: sourceLogs),
                rankingEntries: Self.rankingEntries(for: newFilteredLogs, dimension: selectedDimension),
                resolvedSelectedDay: resolvedDay,
                todayDuration: todayLogs.reduce(0) { $0 + $1.duration },
                selectedDayAppSummaries: Self.groupedSummaries(for: selectedLogs, dimension: .app),
                selectedDayDomainSummaries: Self.groupedSummaries(for: selectedLogs, dimension: .domain),
                selectedDayPdfSummaries: Self.pdfSummaries(for: selectedLogs)
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard token == filterComputationToken else { return }
                rangeLogs = result.filteredLogs
                daySummaries = result.daySummaries
                rangeTotalDuration = result.rangeTotalDuration
                topTopicSummary = result.topTopicSummary
                rankingEntriesCache = result.rankingEntries
                selectedDay = result.resolvedSelectedDay
                todayDuration = result.todayDuration
                selectedDayAppSummaries = result.selectedDayAppSummaries
                selectedDayDomainSummaries = result.selectedDayDomainSummaries
                selectedDayPdfSummaries = result.selectedDayPdfSummaries
            }
        }
    }

    private func refreshRankingEntries() {
        rankingEntriesCache = Self.rankingEntries(for: rangeLogs, dimension: selectedDimension)
    }

    private func refreshSelectedDayData() {
        let effectiveSelectedDay = Self.resolvedSelectedDay(
            currentSelection: selectedDay,
            from: daySummaries,
            calendar: calendar
        )
        let selectedLogs = Self.logs(for: effectiveSelectedDay, in: rangeLogs, calendar: calendar)

        selectedDayAppSummaries = Self.groupedSummaries(for: selectedLogs, dimension: .app)
        selectedDayDomainSummaries = Self.groupedSummaries(for: selectedLogs, dimension: .domain)
        selectedDayPdfSummaries = Self.pdfSummaries(for: selectedLogs)
    }

    nonisolated private static func filteredLogs(from logs: [PreparedLog], using filters: FilterCriteria) -> [PreparedLog] {
        return logs.filter { log in
            if let selectedAppFilter = filters.selectedAppFilter, log.appName != selectedAppFilter {
                return false
            }

            if let selectedDomainFilter = filters.selectedDomainFilter, log.resolvedDomain != selectedDomainFilter {
                return false
            }

            switch filters.selectedContentFilter {
            case .all:
                break
            case .website:
                if !log.isWebsite { return false }
            case .pdf:
                if !log.isPDF { return false }
            }

            if filters.normalizedSearchText.isEmpty {
                return true
            }

            return log.searchableText.contains(filters.normalizedSearchText)
        }
    }

    private func buildFilterOptions(from logs: [PreparedLog], dimension: RankingDimension) -> [FilterOption] {
        Self.rankingEntries(for: logs, dimension: dimension).map {
            FilterOption(name: $0.name, totalTime: $0.totalTime)
        }
    }

    private func sanitizeFilterSelection() {
        if let selectedAppFilter,
           !appFilterOptions.contains(where: { $0.name == selectedAppFilter }) {
            self.selectedAppFilter = nil
        }

        if let selectedDomainFilter,
           !domainFilterOptions.contains(where: { $0.name == selectedDomainFilter }) {
            self.selectedDomainFilter = nil
        }
    }

    nonisolated private static func explicitTopic(for log: PreparedLog) -> TopicDescriptor? {
        if log.isPDF {
            return makeTopicDescriptor(from: log.windowTitle)
        }

        if log.resolvedDomain == "bilibili.com" {
            return makeTopicDescriptor(from: log.windowTitle)
        }

        if isAssistantLog(log) {
            return nil
        }

        if log.isWebsite {
            return nil
        }

        if log.windowTitle == log.appName {
            return nil
        }

        return makeTopicDescriptor(from: log.windowTitle)
    }

    nonisolated private static func inferredTopic(
        for index: Int,
        logs: [PreparedLog],
        explicitTopics: [TopicDescriptor?]
    ) -> TopicDescriptor? {
        let previous = nearestExplicitTopic(from: index, step: -1, logs: logs, explicitTopics: explicitTopics)
        let next = nearestExplicitTopic(from: index, step: 1, logs: logs, explicitTopics: explicitTopics)

        switch (previous, next) {
        case let (left?, right?) where left.topic.canonicalName == right.topic.canonicalName:
            return left.topic
        case let (left?, right?):
            return left.distance <= right.distance ? left.topic : right.topic
        case let (left?, nil):
            return left.topic
        case let (nil, right?):
            return right.topic
        default:
            return nil
        }
    }

    nonisolated private static func nearestExplicitTopic(
        from index: Int,
        step: Int,
        logs: [PreparedLog],
        explicitTopics: [TopicDescriptor?]
    ) -> (topic: TopicDescriptor, distance: TimeInterval)? {
        let maxBridgeGap: TimeInterval = 45 * 60
        var cursor = index + step
        let originDate = logs[index].startTime

        while explicitTopics.indices.contains(cursor) {
            if let topic = explicitTopics[cursor] {
                let distance = abs(logs[cursor].startTime.timeIntervalSince(originDate))
                return distance <= maxBridgeGap ? (topic, distance) : nil
            }
            cursor += step
        }

        return nil
    }

    nonisolated private static func isAssistantLog(_ log: PreparedLog) -> Bool {
        guard let domain = log.resolvedDomain?.lowercased() else {
            return false
        }

        return [
            "chatgpt.com",
            "openai.com",
            "claude.ai",
            "deepseek.com",
            "gemini.google.com",
            "doubao.com",
            "yuanbao.tencent.com"
        ].contains(domain)
    }

    nonisolated private static func makeTopicDescriptor(from title: String) -> TopicDescriptor? {
        let cleaned = cleanedTopicTitle(from: title)
        guard !cleaned.isEmpty else { return nil }
        let canonical = canonicalTopicTitle(from: cleaned)
        guard !canonical.isEmpty else { return nil }
        return TopicDescriptor(canonicalName: canonical, displayName: cleaned)
    }

    nonisolated private static func cleanedTopicTitle(from title: String) -> String {
        var cleaned = title
            .replacingOccurrences(of: " (Bilibili)", with: "")
            .replacingOccurrences(of: ".pdf", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let separatorIndex = cleaned.firstIndex(of: "|") {
            cleaned = String(cleaned[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    nonisolated private static func canonicalTopicTitle(from title: String) -> String {
        let lowercased = title.lowercased()
        let components = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components
            .filter { $0.count >= 2 }
            .joined(separator: " ")
    }

    nonisolated private static func topTopicSummary(in logs: [PreparedLog]) -> TopicDurationSummary? {
        let sortedLogs = logs.sorted { $0.startTime < $1.startTime }
        guard !sortedLogs.isEmpty else { return nil }

        let explicitTopics = sortedLogs.map { explicitTopic(for: $0) }
        let assignments = sortedLogs.enumerated().compactMap { index, log -> TopicAssignment? in
            if let explicitTopic = explicitTopics[index] {
                return TopicAssignment(
                    canonicalName: explicitTopic.canonicalName,
                    displayName: explicitTopic.displayName,
                    duration: log.duration
                )
            }

            guard isAssistantLog(log),
                  let inferredTopic = inferredTopic(for: index, logs: sortedLogs, explicitTopics: explicitTopics) else {
                return nil
            }

            return TopicAssignment(
                canonicalName: inferredTopic.canonicalName,
                displayName: inferredTopic.displayName,
                duration: log.duration
            )
        }

        let grouped = Dictionary(grouping: assignments, by: \.canonicalName)
        return grouped.compactMap { canonicalName, topicAssignments in
            guard let displayName = topicAssignments.first?.displayName else { return nil }
            return TopicDurationSummary(
                canonicalName: canonicalName,
                displayName: displayName,
                totalTime: topicAssignments.reduce(0) { $0 + $1.duration }
            )
        }
        .sorted {
            if $0.totalTime == $1.totalTime {
                return $0.displayName < $1.displayName
            }
            return $0.totalTime > $1.totalTime
        }
        .first
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

        let whitelistSnapshot = WhitelistSnapshot(whitelist: whitelist)
        let filters = activeFilters()

        let logsToDelete = allLogs.compactMap { log -> (ActivityLog, PreparedLog)? in
            guard let prepared = PreparedLog(log: log, whitelist: whitelistSnapshot, calendar: calendar) else {
                return nil
            }
            guard selectedRange.contains(prepared.startTime, calendar: calendar) else {
                return nil
            }
            guard calendar.isDate(prepared.startTime, inSameDayAs: selectedDay) else {
                return nil
            }
            guard Self.filteredLogs(from: [prepared], using: filters).isEmpty == false else {
                return nil
            }
            return (log, prepared)
        }
        .filter { _, prepared in
            switch category {
            case .app:
                return Self.rankingKey(for: prepared, dimension: .app) == summaryName
                    && Self.detailKey(for: prepared, dimension: .app) == detailName
            case .domain:
                return Self.rankingKey(for: prepared, dimension: .domain) == summaryName
                    && Self.detailKey(for: prepared, dimension: .domain) == detailName
            case .pdf:
                return prepared.isPDF && prepared.windowTitle == summaryName && prepared.windowTitle == detailName
            }
        }
        .map(\.0)

        guard !logsToDelete.isEmpty else { return }

        for log in logsToDelete {
            modelContext.delete(log)
        }

        try? modelContext.save()
        refreshRangeData()
    }

    private func updateSelectedDay(_ day: Date) {
        if !isSameDay(selectedDay, day) {
            selectedDay = day
        }
        refreshSelectedDayData()
    }

    private func scheduleSearchRefresh() {
        searchDebounceTask?.cancel()

        let normalized = normalizedSearchText(from: searchText)
        if normalized.isEmpty {
            appliedSearchText = ""
            return
        }

        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                appliedSearchText = normalized
            }
        }
    }

    private func normalizedSearchText(from text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func activeFilters() -> FilterCriteria {
        FilterCriteria(
            normalizedSearchText: appliedSearchText,
            selectedContentFilter: selectedContentFilter,
            selectedAppFilter: selectedAppFilter,
            selectedDomainFilter: selectedDomainFilter
        )
    }

    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)时\(minutes)分"
        }
        return "\(minutes)分"
    }

    private func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let remainingSeconds = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%02d时%02d分%02d秒", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d分%02d秒", minutes, remainingSeconds)
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
        appliedSearchText = ""
        selectedContentFilter = .all
        selectedAppFilter = nil
        selectedDomainFilter = nil
    }
}

private enum StatisticsRange: String, CaseIterable, Identifiable, Sendable {
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

private enum ContentFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case website
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .website: return "网站"
        case .pdf: return "PDF"
        }
    }
}

private enum RankingDimension: String, CaseIterable, Identifiable, Sendable {
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

private enum DetailCategory: Sendable {
    case app
    case domain
    case pdf
}

private struct DaySummary: Identifiable, Sendable {
    let date: Date
    let totalTime: TimeInterval

    var id: Date { date }
}

private struct RankingEntry: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval

    var id: String { name }
}

private struct FilterOption: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval

    var id: String { name }
}

private struct GroupedSummary: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval
    let details: [SummaryDetail]

    var id: String { name }
}

private struct SummaryDetail: Identifiable, Sendable {
    let name: String
    let subtitle: String?
    let totalTime: TimeInterval

    var id: String { "\(name)|\(subtitle ?? "")" }
}

private struct TopicDurationSummary: Sendable {
    let canonicalName: String
    let displayName: String
    let totalTime: TimeInterval
}

private struct TopicAssignment: Sendable {
    let canonicalName: String
    let displayName: String
    let duration: TimeInterval
}

private struct TopicDescriptor: Sendable {
    let canonicalName: String
    let displayName: String
}

private struct FilterCriteria: Sendable {
    let normalizedSearchText: String
    let selectedContentFilter: ContentFilter
    let selectedAppFilter: String?
    let selectedDomainFilter: String?
}

private struct FilterComputationResult: Sendable {
    let filteredLogs: [PreparedLog]
    let daySummaries: [DaySummary]
    let rangeTotalDuration: TimeInterval
    let topTopicSummary: TopicDurationSummary?
    let rankingEntries: [RankingEntry]
    let resolvedSelectedDay: Date?
    let todayDuration: TimeInterval
    let selectedDayAppSummaries: [GroupedSummary]
    let selectedDayDomainSummaries: [GroupedSummary]
    let selectedDayPdfSummaries: [GroupedSummary]
}

private struct WhitelistSnapshot: Sendable {
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

private struct PreparedLog: Identifiable, Sendable {
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
        if log.windowTitle.contains("权限") || log.windowTitle.contains("未知") || log.appName.isEmpty {
            return nil
        }

        let lowercasedAppName = log.appName.lowercased()
        let isWebsite = Self.isBrowserApp(log.appName)
        let isWhitelistedApp = whitelist.lowercasedApps.contains { whitelistedApp in
            whitelistedApp == lowercasedAppName
                || whitelistedApp.contains(lowercasedAppName)
                || lowercasedAppName.contains(whitelistedApp)
        }

        guard isWhitelistedApp else { return nil }

        let resolvedDomain = Self.resolveDomain(for: log, whitelist: whitelist)
        let lowercasedWindowTitle = log.windowTitle.lowercased()
        if isWebsite && !lowercasedWindowTitle.contains("网页加载中") && resolvedDomain == nil {
            return nil
        }

        self.identity = PreparedLogIdentity(
            appName: log.appName,
            windowTitle: log.windowTitle,
            startTime: log.startTime,
            duration: log.duration,
            domain: log.domain,
            bilibiliIdentifier: log.bilibiliIdentifier,
            fullUrl: log.fullUrl
        )
        self.appName = log.appName
        self.windowTitle = log.windowTitle
        self.startTime = log.startTime
        self.dayStart = calendar.startOfDay(for: log.startTime)
        self.duration = log.duration
        self.resolvedDomain = resolvedDomain
        self.bilibiliIdentifier = log.bilibiliIdentifier
        self.fullUrl = log.fullUrl
        self.searchableText = [
            log.appName,
            log.windowTitle,
            resolvedDomain ?? "",
            log.fullUrl ?? ""
        ]
        .joined(separator: "\n")
        .lowercased()
        self.isPDF = Self.isPDF(log)
        self.isWebsite = isWebsite
    }

    private static func resolveDomain(for log: ActivityLog, whitelist: WhitelistSnapshot) -> String? {
        if let domain = log.domain, whitelist.domains.contains(domain) {
            return domain
        }

        let lowercasedWindowTitle = log.windowTitle.lowercased()
        return whitelist.domainKeywords.first { entry in
            lowercasedWindowTitle.contains(entry.keyword)
                || (entry.keyword == "bilibili" && lowercasedWindowTitle.contains("哔哩哔哩"))
        }?.domain
    }

    private static func isPDF(_ log: ActivityLog) -> Bool {
        let lowercasedAppName = log.appName.lowercased()
        let lowercasedTitle = log.windowTitle.lowercased()
        return (lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview"))
            && lowercasedTitle.contains(".pdf")
    }

    private static func isBrowserApp(_ appName: String) -> Bool {
        let lowercasedAppName = appName.lowercased()
        return lowercasedAppName.contains("safari")
            || lowercasedAppName.contains("chrome")
            || lowercasedAppName.contains("edge")
    }
}

private struct PreparedLogIdentity: Hashable, Sendable {
    let appName: String
    let windowTitle: String
    let startTime: Date
    let duration: TimeInterval
    let domain: String?
    let bilibiliIdentifier: String?
    let fullUrl: String?
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
                    Button("全部应用") {
                        selectedAppFilter = nil
                    }

                    if !appOptions.isEmpty {
                        Divider()
                    }

                    ForEach(appOptions.prefix(12)) { option in
                        Button {
                            selectedAppFilter = option.name
                        } label: {
                            HStack {
                                Text(option.name)
                                Spacer()
                                Text(formatDuration(option.totalTime))
                            }
                        }
                    }
                } label: {
                    FilterChip(
                        title: "应用",
                        value: selectedAppFilter ?? "全部应用"
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    Button("全部域名") {
                        selectedDomainFilter = nil
                    }

                    if !domainOptions.isEmpty {
                        Divider()
                    }

                    ForEach(domainOptions.prefix(12)) { option in
                        Button {
                            selectedDomainFilter = option.name
                        } label: {
                            HStack {
                                Text(option.name)
                                Spacer()
                                Text(formatDuration(option.totalTime))
                            }
                        }
                    }
                } label: {
                    FilterChip(
                        title: "域名",
                        value: selectedDomainFilter ?? "全部域名"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(20)
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty
            || selectedContentFilter != .all
            || selectedAppFilter != nil
            || selectedDomainFilter != nil
    }
}

private struct FilterChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.6))
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
                Text("每日时长")
                    .font(.system(size: 18, weight: .semibold))
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
                    Text("最高值")
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
            Text("日期")
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
            Text("使用时间总排行")
                .font(.system(size: 18, weight: .semibold))

            Picker("排行维度", selection: $selectedDimension) {
                ForEach(RankingDimension.allCases) { dimension in
                    Text(dimension.title).tag(dimension)
                }
            }
            .pickerStyle(.segmented)

            if rankingEntries.isEmpty {
                Text("无数据")
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
                    Text("当日明细")
                        .font(.system(size: 18, weight: .semibold))
                    Text(selectedDay.map(formatDate) ?? "暂无日期")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if appSummaries.isEmpty && domainSummaries.isEmpty && pdfSummaries.isEmpty {
                Text("无记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 12) {
                    CategorySummaryGroup(
                        title: "应用",
                        emptyText: "无应用记录",
                        summaries: appSummaries,
                        formatDuration: formatDuration,
                        onDelete: { summaryName, detailName in
                            onDelete(.app, summaryName, detailName)
                        }
                    )

                    CategorySummaryGroup(
                        title: "域名",
                        emptyText: "无域名记录",
                        summaries: domainSummaries,
                        formatDuration: formatDuration,
                        onDelete: { summaryName, detailName in
                            onDelete(.domain, summaryName, detailName)
                        }
                    )

                    CategorySummaryGroup(
                        title: "PDF",
                        emptyText: "无 PDF 记录",
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
                            Label("删除记录", systemImage: "trash")
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

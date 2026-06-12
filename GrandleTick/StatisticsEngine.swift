import Foundation
import SwiftData

@MainActor
@Observable
final class StatisticsEngine {
    var baseRangeLogs: [PreparedLog] = []
    var rangeLogs: [PreparedLog] = []
    var daySummaries: [DaySummary] = []
    var rankingEntries: [RankingEntry] = []
    var rangeTotalDuration: TimeInterval = 0
    var todayDuration: TimeInterval = 0

    var selectedDay: Date?
    var selectedDayAppSummaries: [GroupedSummary] = []
    var selectedDayDomainSummaries: [GroupedSummary] = []
    var selectedDayPdfSummaries: [GroupedSummary] = []
    var topAppSummary: AppDurationSummary?

    var appFilterOptions: [FilterOption] = []
    var domainFilterOptions: [FilterOption] = []

    private var filterComputationTask: Task<Void, Never>?
    private var filterComputationToken: UInt = 0
    private let calendar = Calendar.current

    // 1. 刷新指定时间范围内的原始数据。
    // 这是所有过滤和聚合的基础。
    func refreshBaseData(for range: StatisticsRange, modelContext: ModelContext, whitelist: WhitelistManager) {
        filterComputationTask?.cancel()

        let whitelistSnapshot = WhitelistSnapshot(whitelist: whitelist)
        let sourceLogs = fetchLogs(for: range, modelContext: modelContext)
        let newRangeLogs = sourceLogs.compactMap { log in
            PreparedLog(log: log, whitelist: whitelistSnapshot, calendar: calendar)
        }

        baseRangeLogs = newRangeLogs
        appFilterOptions = buildFilterOptions(from: newRangeLogs, dimension: .app)
        domainFilterOptions = buildFilterOptions(from: newRangeLogs, dimension: .domain)
    }

    // 2. 根据用户设置的过滤条件（搜索词、应用、域名、内容类型）重新计算展示数据。
    // 包含异步聚合逻辑，避免阻塞主线程。
    func applyFilters(
        searchText: String,
        contentFilter: ContentFilter,
        appFilter: String?,
        domainFilter: String?,
        dimension: RankingDimension
    ) {
        filterComputationTask?.cancel()
        filterComputationToken &+= 1

        let token = filterComputationToken
        let sourceLogs = baseRangeLogs
        let filters = FilterCriteria(
            normalizedSearchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selectedContentFilter: contentFilter,
            selectedAppFilter: appFilter,
            selectedDomainFilter: domainFilter
        )
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
                topAppSummary: Self.topAppSummary(in: sourceLogs),
                rankingEntries: Self.rankingEntries(for: newFilteredLogs, dimension: dimension),
                resolvedSelectedDay: resolvedDay,
                todayDuration: todayLogs.reduce(0) { $0 + $1.duration },
                selectedDayAppSummaries: Self.groupedSummaries(for: selectedLogs, dimension: .app),
                selectedDayDomainSummaries: Self.groupedSummaries(for: selectedLogs, dimension: .domain),
                selectedDayPdfSummaries: Self.pdfSummaries(for: selectedLogs)
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard token == self.filterComputationToken else { return }
                self.rangeLogs = result.filteredLogs
                self.daySummaries = result.daySummaries
                self.rangeTotalDuration = result.rangeTotalDuration
                self.topAppSummary = result.topAppSummary
                self.rankingEntries = result.rankingEntries
                self.selectedDay = result.resolvedSelectedDay
                self.todayDuration = result.todayDuration
                self.selectedDayAppSummaries = result.selectedDayAppSummaries
                self.selectedDayDomainSummaries = result.selectedDayDomainSummaries
                self.selectedDayPdfSummaries = result.selectedDayPdfSummaries
            }
        }
    }

    // 3. 切换排行维度（应用/网站/条目）时，快速更新排行榜缓存。
    func updateRanking(for dimension: RankingDimension) {
        rankingEntries = Self.rankingEntries(for: rangeLogs, dimension: dimension)
    }

    // 4. 更新所选日期的明细数据。
    func updateSelectedDay(_ day: Date) {
        if selectedDay != day {
            selectedDay = day
        }
        let selectedLogs = Self.logs(for: day, in: rangeLogs, calendar: calendar)
        selectedDayAppSummaries = Self.groupedSummaries(for: selectedLogs, dimension: .app)
        selectedDayDomainSummaries = Self.groupedSummaries(for: selectedLogs, dimension: .domain)
        selectedDayPdfSummaries = Self.pdfSummaries(for: selectedLogs)
    }

    // MARK: - Private Helper Logic

    private func fetchLogs(for range: StatisticsRange, modelContext: ModelContext) -> [ActivityLog] {
        do {
            let descriptor = range.fetchDescriptor(calendar: calendar)
            return try modelContext.fetch(descriptor)
        } catch {
            print("[StatisticsEngine] 抓取日志失败: \(error.localizedDescription)")
            return []
        }
    }

    private func buildFilterOptions(from logs: [PreparedLog], dimension: RankingDimension) -> [FilterOption] {
        Self.rankingEntries(for: logs, dimension: dimension).map {
            FilterOption(name: $0.name, totalTime: $0.totalTime)
        }
    }

    // MARK: - Static Processing (Thread Safe)

    nonisolated private static func filteredLogs(from logs: [PreparedLog], using filters: FilterCriteria) -> [PreparedLog] {
        return logs.filter { log in
            if let selectedAppFilter = filters.selectedAppFilter, log.appName != selectedAppFilter {
                return false
            }
            if let selectedDomainFilter = filters.selectedDomainFilter, log.resolvedDomain != selectedDomainFilter {
                return false
            }
            switch filters.selectedContentFilter {
            case .all: break
            case .website: if !log.isWebsite { return false }
            case .pdf: if !log.isPDF { return false }
            }
            if filters.normalizedSearchText.isEmpty { return true }
            return log.searchableText.contains(filters.normalizedSearchText)
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
        .sorted { $0.totalTime > $1.totalTime }
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
                    details: [SummaryDetail(name: key, subtitle: groupedLogs.first?.appName, totalTime: groupedLogs.reduce(0) { $0 + $1.duration })]
                )
            }
            let detailGroups = Dictionary(grouping: groupedLogs) { detailKey(for: $0, dimension: dimension) }
            let details = detailGroups.map { detailKey, detailLogs in
                SummaryDetail(name: detailKey, subtitle: detailSubtitle(for: detailLogs, dimension: dimension), totalTime: detailLogs.reduce(0) { $0 + $1.duration })
            }
            .sorted { $0.totalTime > $1.totalTime }
            return GroupedSummary(name: key, totalTime: groupedLogs.reduce(0) { $0 + $1.duration }, details: details)
        }
        .sorted { $0.totalTime > $1.totalTime }
    }

    nonisolated private static func pdfSummaries(for logs: [PreparedLog]) -> [GroupedSummary] {
        let pdfLogs = logs.filter(\.isPDF)
        let grouped = Dictionary(grouping: pdfLogs) { $0.windowTitle }
        return grouped.map { title, titleLogs in
            GroupedSummary(name: title, totalTime: titleLogs.reduce(0) { $0 + $1.duration }, details: [SummaryDetail(name: title, subtitle: titleLogs.first?.appName, totalTime: titleLogs.reduce(0) { $0 + $1.duration })])
        }
        .sorted { $0.totalTime > $1.totalTime }
    }

    nonisolated private static func topAppSummary(in logs: [PreparedLog]) -> AppDurationSummary? {
        let filteredLogs = logs.filter { !isEntertainmentLog($0) }
        return rankingEntries(for: filteredLogs, dimension: .app).first.map {
            AppDurationSummary(displayName: $0.name, totalTime: $0.totalTime)
        }
    }

    nonisolated private static func resolvedSelectedDay(currentSelection: Date?, from daySummaries: [DaySummary], calendar: Calendar) -> Date? {
        guard !daySummaries.isEmpty else { return nil }
        if let currentSelection, daySummaries.contains(where: { calendar.isDate($0.date, inSameDayAs: currentSelection) }) {
            return currentSelection
        }
        return daySummaries.last?.date
    }

    nonisolated private static func logs(for day: Date?, in logs: [PreparedLog], calendar: Calendar) -> [PreparedLog] {
        guard let day else { return [] }
        return logs.filter { calendar.isDate($0.startTime, inSameDayAs: day) }
    }

    nonisolated private static func isEntertainmentLog(_ log: PreparedLog) -> Bool {
        log.resolvedDomain == "bilibili.com" && log.windowTitle == AppConfig.bilibiliEntertainmentTitle
    }

    nonisolated private static func rankingKey(for log: PreparedLog, dimension: RankingDimension) -> String? {
        switch dimension {
        case .app: return log.appName
        case .domain: return log.resolvedDomain
        case .item: return log.windowTitle
        }
    }

    nonisolated private static func detailKey(for log: PreparedLog, dimension: RankingDimension) -> String {
        switch dimension {
        case .app: return log.windowTitle
        case .domain: return log.resolvedDomain ?? log.appName
        case .item: return log.resolvedDomain ?? log.appName
        }
    }

    nonisolated private static func detailSubtitle(for logs: [PreparedLog], dimension: RankingDimension) -> String? {
        guard dimension == .item else { return nil }
        let sources = Set(logs.map { $0.resolvedDomain ?? $0.appName }).sorted()
        return sources.isEmpty ? nil : sources.joined(separator: " · ")
    }
}

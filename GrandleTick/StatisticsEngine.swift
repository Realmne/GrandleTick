import Foundation
import SwiftData

// MARK: - Supporting Enums and Models

/// 统计排行维度：应用、域名或具体窗口项
enum RankingDimension: String, CaseIterable, Identifiable, Sendable {
    case app, domain, item
    var id: String { rawValue }
}

/// 内容类型过滤器
enum ContentFilter: String, CaseIterable, Identifiable, Sendable {
    case all, website, pdf
    var id: String { rawValue }
}

/// 详细列表分类类型
enum DetailCategory: String, Sendable {
    case app, domain, pdf
}

/// 每日总计时长
struct DaySummary: Identifiable, Sendable {
    let date: Date
    let totalTime: TimeInterval
    var id: Date { date }
}

/// 排行榜单项
struct RankingEntry: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval
    var id: String { name }
}

/// 过滤选项（供下拉菜单展示）
struct FilterOption: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval
    var id: String { name }
}

/// 按维度分组的明细数据
struct GroupedSummary: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval
    let details: [SummaryDetail]
    var id: String { name }
}

/// 分组下的具体明细子项
struct SummaryDetail: Identifiable, Sendable {
    let name: String
    let subtitle: String?
    let totalTime: TimeInterval
    var id: String { "\(name)|\(subtitle ?? "")" }
}

/// 最高耗时应用概览
struct AppDurationSummary: Sendable {
    let displayName: String
    let totalTime: TimeInterval
}

/// 过滤器输入条件结构体
struct FilterCriteria: Sendable {
    let normalizedSearchText: String
    let selectedContentFilter: ContentFilter
    let selectedAppFilter: String?
    let selectedDomainFilter: String?
}

/// 白名单规则的内存快照，用于线程安全的后台日志过滤与处理
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

/// 处理且规范化后的用户活动日志
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
    let isStudy: Bool
    let pdfIdentifier: String?
    var id: PreparedLogIdentity { identity }

    var endTime: Date {
        startTime.addingTimeInterval(duration)
    }

    init?(log: ActivityLog, whitelist: WhitelistSnapshot, calendar: Calendar) {
        // 1. 过滤掉无意义的系统权限提示或未知/无效空日志
        if log.windowTitle.contains("权限") || log.windowTitle.contains("未知") || log.appName.isEmpty { return nil }
        
        let lowercasedAppName = log.appName.lowercased()
        let isWebsite = lowercasedAppName.contains("safari") || lowercasedAppName.contains("chrome") || lowercasedAppName.contains("edge")
        
        // 2. 解析域名。如果有域名，无论是否在白名单，均保留以支持网站统计与分类。
        let resolvedDomain = Self.resolveDomain(for: log, whitelist: whitelist)
        
        self.identity = PreparedLogIdentity(
            appName: log.appName,
            windowTitle: log.windowTitle,
            startTime: log.startTime,
            duration: log.duration,
            domain: log.domain,
            bilibiliIdentifier: log.bilibiliIdentifier,
            fullUrl: log.fullUrl,
            pdfIdentifier: log.pdfIdentifier
        )
        self.appName = log.appName
        self.windowTitle = log.windowTitle
        self.startTime = log.startTime
        self.dayStart = calendar.startOfDay(for: log.startTime)
        self.duration = log.duration
        self.resolvedDomain = resolvedDomain
        self.bilibiliIdentifier = log.bilibiliIdentifier
        self.fullUrl = log.fullUrl
        self.pdfIdentifier = log.pdfIdentifier
        
        // 3. 构建搜索文本，以便后续过滤与检索
        self.searchableText = [log.appName, log.windowTitle, resolvedDomain ?? "", log.fullUrl ?? ""].joined(separator: "\n").lowercased()
        
        // 4. PDF 判断：必须是预览 App 且文件名以 .pdf 结尾
        let lowercasedTitle = log.windowTitle.lowercased()
        let isPDF = (lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview")) && lowercasedTitle.contains(".pdf")
        self.isPDF = isPDF
        self.isWebsite = isWebsite
        
        // 5. 分类学习 vs 娱乐/休闲。白名单外的所有其它应用均归入娱乐/休闲。
        let isStudy: Bool
        if isWebsite {
            let isWhitelistedDomain = resolvedDomain.flatMap { domain in
                whitelist.domains.contains { $0.lowercased() == domain.lowercased() }
            } ?? false
            // B 站视频只有 bilibiliIdentifier 非空（API 确认知识区）才算学习，
            // 与实时弹窗 isStudyActive 的判断逻辑保持完全一致。
            // 不能用 windowTitle == "娱乐" 判断，因为 URL 获取失败的兜底路径会把 windowTitle 写成 "Bilibili"。
            if resolvedDomain == "bilibili.com" {
                isStudy = log.bilibiliIdentifier != nil
            } else {
                isStudy = isWhitelistedDomain
            }
        } else if lowercasedAppName.contains("预览") || lowercasedAppName.contains("preview") {
            isStudy = isPDF
        } else {
            let isWhitelistedApp = whitelist.lowercasedApps.contains { $0 == lowercasedAppName || $0.contains(lowercasedAppName) || lowercasedAppName.contains($0) }
            isStudy = isWhitelistedApp
        }
        self.isStudy = isStudy
    }

    private static func resolveDomain(for log: ActivityLog, whitelist: WhitelistSnapshot) -> String? {
        // 如果数据库日志里有解析好的 domain，优先直接返回它以保留一般网站的域名数据
        if let domain = log.domain, !domain.isEmpty { return domain }
        // 兜底从窗口标题中尝试提取白名单域名
        let lowercasedWindowTitle = log.windowTitle.lowercased()
        return whitelist.domainKeywords.first { entry in lowercasedWindowTitle.contains(entry.keyword) || (entry.keyword == "bilibili" && lowercasedWindowTitle.contains("哔哩哔哩")) }?.domain
    }
}

/// 用于唯一标识一条日志的结构体
struct PreparedLogIdentity: Hashable, Sendable {
    let appName: String
    let windowTitle: String
    let startTime: Date
    let duration: TimeInterval
    let domain: String?
    let bilibiliIdentifier: String?
    let fullUrl: String?
    let pdfIdentifier: String?
}

/// 周期对比数据模型
struct ReportComparison: Sendable {
    let totalDurationDelta: TimeInterval
    let totalDurationChangeRate: Double?
    let activeDaysDelta: Int
}

/// 学习活跃时段分类
enum ReportTimeSlot: String, Sendable {
    case morning, afternoon, evening, lateNight
    var title: String {
        switch self {
        case .morning: return "上午"
        case .afternoon: return "下午"
        case .evening: return "晚上"
        case .lateNight: return "深夜"
        }
    }
}

/// 统一时间周期与范围分类
enum StatisticsRange: String, CaseIterable, Identifiable, Sendable {
    case today, week, month, year, all
    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .today: return "今天"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "本年"
        case .all: return "全部"
        }
    }

    var title: String {
        switch self {
        case .today: return "今天"
        case .week: return "本周回顾"
        case .month: return "本月回顾"
        case .year: return "本年回顾"
        case .all: return "全部历史"
        }
    }

    var previousTitle: String {
        switch self {
        case .today: return "昨天"
        case .week: return "上周"
        case .month: return "上月"
        case .year: return "去年"
        case .all: return "前一期"
        }
    }
}

/// 后台计算结果的封装包，用于批量更新主线程状态
struct FilterComputationResult: Sendable {
    let filteredLogs: [PreparedLog]
    let previousFilteredLogs: [PreparedLog]
    let daySummaries: [DaySummary]
    let rangeTotalDuration: TimeInterval
    let topAppSummary: AppDurationSummary?
    let rankingEntries: [RankingEntry]
    let resolvedSelectedDay: Date?
    let todayDuration: TimeInterval

    // 选中日期的详情聚合数据
    let selectedDayAppSummaries: [GroupedSummary]
    let selectedDayDomainSummaries: [GroupedSummary]
    let selectedDayPdfSummaries: [GroupedSummary]

    // 热门排行
    let topWebsites: [RankingEntry]
    let topPDFs: [RankingEntry]

    // 合并自报告的数据指标
    let studyDuration: TimeInterval
    let entertainmentDuration: TimeInterval
    let activeDays: Int
    let averageDailyDuration: TimeInterval
    let strongestDay: DaySummary?
    let shortestActiveDay: DaySummary?
    let longestStreak: Int
    let websiteDuration: TimeInterval
    let pdfDuration: TimeInterval
    let primaryTimeSlot: ReportTimeSlot?
    let earliestStudyStart: Date?
    let latestStudyEnd: Date?
    let comparison: ReportComparison?
    let hourlyDurations: [Double]
}

// MARK: - StatisticsEngine Implementation

@MainActor
@Observable
final class StatisticsEngine {
    // 基础数据与主界面日志
    var baseRangeLogs: [PreparedLog] = []
    var rangeLogs: [PreparedLog] = []
    var previousRangeLogs: [PreparedLog] = []

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

    // 统一周期与对比状态
    var referenceDate: Date = Date()
    var canShowPreviousPeriod = false
    var canShowNextPeriod = false

    // 热门排行缓存
    var topWebsites: [RankingEntry] = []
    var topPDFs: [RankingEntry] = []

    // 合并后的报告高级统计量
    var studyDuration: TimeInterval = 0
    var entertainmentDuration: TimeInterval = 0
    var activeDays: Int = 0
    var averageDailyDuration: TimeInterval = 0
    var strongestDay: DaySummary?
    var shortestActiveDay: DaySummary?
    var longestStreak: Int = 0

    var websiteDuration: TimeInterval = 0
    var pdfDuration: TimeInterval = 0
    var primaryTimeSlot: ReportTimeSlot?
    var earliestStudyStart: Date?
    var latestStudyEnd: Date?
    var comparison: ReportComparison?
    var hourlyDurations: [Double] = Array(repeating: 0.0, count: 24)

    private var filterComputationTask: Task<Void, Never>?
    private var filterComputationToken: UInt = 0
    private let calendar = Calendar.current

    // MARK: - Data Refreshing

    /// 刷新选定周期下的底量数据，执行数据库抓取并清洗
    func refreshBaseData(for range: StatisticsRange, modelContext: ModelContext, whitelist: WhitelistManager) {
        filterComputationTask?.cancel()

        // 1. 根据当前参考日期和时间周期计算出要抓取的数据时间跨度。
        let whitelistSnapshot = WhitelistSnapshot(whitelist: whitelist)
        let sourceLogs = fetchLogs(for: range, referenceDate: referenceDate, modelContext: modelContext)

        // 2. 将原始日志转化为格式化日志（PreparedLog）结构。
        let newRangeLogs = sourceLogs.compactMap { log in
            PreparedLog(log: log, whitelist: whitelistSnapshot, calendar: calendar)
        }

        // 3. 将全局状态缓存并生成筛选器的快捷选项。
        baseRangeLogs = newRangeLogs
        appFilterOptions = buildFilterOptions(from: newRangeLogs, dimension: .app)
        domainFilterOptions = buildFilterOptions(from: newRangeLogs, dimension: .domain)
    }

    /// 应用过滤条件（如搜索字词、内容分类、应用白名单等），在独立线程中执行大量聚合和报告生成计算
    func applyFilters(
        searchText: String,
        contentFilter: ContentFilter,
        appFilter: String?,
        domainFilter: String?,
        dimension: RankingDimension,
        range: StatisticsRange
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
        let now = Date()
        let refDate = referenceDate

        // 1. 获取当前周期以及对比上期的 DateInterval 边界。
        let currentInterval = interval(for: range, referenceDate: refDate, currentDate: now)
        let previousInterval = currentInterval.flatMap { self.previousInterval(for: range, currentInterval: $0) }

        filterComputationTask = Task.detached(priority: .userInitiated) {
            // 2. 区分当前时间段与上期对比时间段的日志数据。
            let currentLogs = sourceLogs.filter { log in
                if let current = currentInterval {
                    return log.startTime >= current.start && log.startTime < current.end
                }
                return true
            }
            let prevLogs = sourceLogs.filter { log in
                if let prev = previousInterval {
                    return log.startTime >= prev.start && log.startTime < prev.end
                }
                return false
            }

            // 3. 将搜索、单应用、单域名等筛选规则应用在这两组日志上。
            let newFilteredLogs = Self.applyCriteria(to: currentLogs, using: filters)
            let prevFilteredLogs = Self.applyCriteria(to: prevLogs, using: filters)

            // 4. 将日志区分为学习与娱乐类别，用于后续指标计算。
            let currentStudyLogs = newFilteredLogs.filter { !Self.isEntertainmentLog($0) }
            let previousStudyLogs = prevFilteredLogs.filter { !Self.isEntertainmentLog($0) }
            let currentEntertainmentLogs = newFilteredLogs.filter { Self.isEntertainmentLog($0) }

            // 5. 计算每日的概览图表趋势点和当前选中的天数。
            // 传入 newFilteredLogs (全部日志，用于获取所有活跃天数以保证可在图表上点选) 和 currentStudyLogs (仅学习日志，用于累计专注时长)
            let newDaySummaries = Self.dailySummaries(for: newFilteredLogs, studyLogs: currentStudyLogs)
            let resolvedDay = Self.resolvedSelectedDay(
                currentSelection: currentSelectedDay,
                from: newDaySummaries,
                calendar: calendar
            )
            let todayLogs = Self.logs(for: now, in: newFilteredLogs, calendar: calendar)
            let selectedLogs = Self.logs(for: resolvedDay, in: newFilteredLogs, calendar: calendar)

            // 6. 执行概览卡片数值计算（学习时长、娱乐时长等）。
            let studyDuration = currentStudyLogs.reduce(0) { $0 + $1.duration }
            let entertainmentDuration = currentEntertainmentLogs.reduce(0) { $0 + $1.duration }
            let activeDays = newDaySummaries.filter { $0.totalTime > 0 }.count
            let averageDailyDuration = activeDays > 0 ? studyDuration / Double(activeDays) : 0

            // 7. 计算高峰日（最专注的一天）与低谷日（已完成天数内学习时间最少的一天）。
            let todayStart = calendar.startOfDay(for: now)
            let completedDays = newDaySummaries.filter { $0.date < todayStart }
            let strongestDay = completedDays.max(by: { $0.totalTime < $1.totalTime })
            let shortestActiveDay = completedDays.min(by: { $0.totalTime < $1.totalTime })

            // 8. 连续专注天数、常看载体（PDF/网页）等计算。
            let longestStreak = Self.longestStreak(in: newDaySummaries, calendar: calendar)
            let websiteDuration = currentStudyLogs.filter(\.isWebsite).reduce(0) { $0 + $1.duration }
            let pdfDuration = currentStudyLogs.filter(\.isPDF).reduce(0) { $0 + $1.duration }

            // 9. 时段分布（如最常专注时段、最早最晚专注时刻）。
            let primaryTimeSlot = Self.strongestTimeSlot(in: currentStudyLogs, calendar: calendar)
            let earliestStudyStart = Self.earliestStudyStart(in: currentStudyLogs, calendar: calendar)
            let latestStudyEnd = Self.latestStudyEnd(in: currentStudyLogs, calendar: calendar)

            // 10. 全天 24 小时活跃度曲线的柱状映射（将秒数累计至 24 个小时桶中）。
            var hourlyDurations = Array(repeating: 0.0, count: 24)
            for log in currentStudyLogs {
                let hour = calendar.component(.hour, from: log.startTime)
                hourlyDurations[hour] += log.duration
            }

            // 11. 与上一周期进行同比数据比较。
            let comparison = Self.buildComparison(currentLogs: currentStudyLogs, previousLogs: previousStudyLogs)

            // 12. 提取全周期前3名热门网站和热门PDF
            let topWebsites = Self.rankingEntries(for: currentStudyLogs.filter(\.isWebsite), dimension: .domain).prefix(3).map { $0 }
            let topPDFs = Self.rankingEntries(for: currentStudyLogs.filter(\.isPDF), dimension: .item).prefix(3).map { $0 }

            let result = FilterComputationResult(
                filteredLogs: newFilteredLogs,
                previousFilteredLogs: prevFilteredLogs,
                daySummaries: newDaySummaries,
                rangeTotalDuration: newFilteredLogs.reduce(0) { $0 + $1.duration },
                topAppSummary: Self.topAppSummary(in: sourceLogs),
                rankingEntries: Self.rankingEntries(for: newFilteredLogs, dimension: dimension),
                resolvedSelectedDay: resolvedDay,
                todayDuration: todayLogs.filter { !Self.isEntertainmentLog($0) }.reduce(0) { $0 + $1.duration },
                selectedDayAppSummaries: Self.groupedSummaries(for: selectedLogs, dimension: .app),
                selectedDayDomainSummaries: Self.groupedSummaries(for: selectedLogs, dimension: .domain),
                selectedDayPdfSummaries: Self.pdfSummaries(for: selectedLogs),
                topWebsites: topWebsites,
                topPDFs: topPDFs,
                studyDuration: studyDuration,
                entertainmentDuration: entertainmentDuration,
                activeDays: activeDays,
                averageDailyDuration: averageDailyDuration,
                strongestDay: strongestDay,
                shortestActiveDay: shortestActiveDay,
                longestStreak: longestStreak,
                websiteDuration: websiteDuration,
                pdfDuration: pdfDuration,
                primaryTimeSlot: primaryTimeSlot,
                earliestStudyStart: earliestStudyStart,
                latestStudyEnd: latestStudyEnd,
                comparison: comparison,
                hourlyDurations: hourlyDurations
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard token == self.filterComputationToken else { return }
                self.rangeLogs = result.filteredLogs
                self.previousRangeLogs = result.previousFilteredLogs
                self.daySummaries = result.daySummaries
                self.rangeTotalDuration = result.rangeTotalDuration
                self.topAppSummary = result.topAppSummary
                self.rankingEntries = result.rankingEntries
                self.selectedDay = result.resolvedSelectedDay
                self.todayDuration = result.todayDuration
                self.selectedDayAppSummaries = result.selectedDayAppSummaries
                self.selectedDayDomainSummaries = result.selectedDayDomainSummaries
                self.selectedDayPdfSummaries = result.selectedDayPdfSummaries
                self.topWebsites = result.topWebsites
                self.topPDFs = result.topPDFs

                // 更新合并生成的报告分析指标
                self.studyDuration = result.studyDuration
                self.entertainmentDuration = result.entertainmentDuration
                self.activeDays = result.activeDays
                self.averageDailyDuration = result.averageDailyDuration
                self.strongestDay = result.strongestDay
                self.shortestActiveDay = result.shortestActiveDay
                self.longestStreak = result.longestStreak
                self.websiteDuration = result.websiteDuration
                self.pdfDuration = result.pdfDuration
                self.primaryTimeSlot = result.primaryTimeSlot
                self.earliestStudyStart = result.earliestStudyStart
                self.latestStudyEnd = result.latestStudyEnd
                self.comparison = result.comparison
                self.hourlyDurations = result.hourlyDurations

                // 根据是否有上周期数据更新翻页按钮的可用状态
                self.updatePaginationState(range: range, now: now)
            }
        }
    }

    /// 切换排行榜排序维度（应用 / 域名 / 网页标题）时的极速响应函数
    func updateRanking(for dimension: RankingDimension) {
        rankingEntries = Self.rankingEntries(for: rangeLogs, dimension: dimension)
    }

    /// 用户在每日趋势图中点击选择不同日期时，快速更新详情卡片数据
    func updateSelectedDay(_ day: Date) {
        if selectedDay != day {
            selectedDay = day
        }
        let selectedLogs = Self.logs(for: day, in: rangeLogs, calendar: calendar)
        selectedDayAppSummaries = Self.groupedSummaries(for: selectedLogs, dimension: .app)
        selectedDayDomainSummaries = Self.groupedSummaries(for: selectedLogs, dimension: .domain)
        selectedDayPdfSummaries = Self.pdfSummaries(for: selectedLogs)
    }

    /// 从数据库中删除特定日期和分类下的日志，并持久化保存
    func deleteLogs(on selectedDay: Date?, category: DetailCategory, summaryName: String, detailName: String, modelContext: ModelContext) {
        guard let selectedDay else { return }

        // 1. 按照当前选中日期以及特定应用/域名/PDF定位需清理的日志标识。
        let logsToDelete = rangeLogs.filter { prepared in
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

        // 2. 从持久化上下文中逐个匹配并删除。
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

        // 3. 执行物理保存。
        try? modelContext.save()
    }

    /// 前后翻页逻辑，基于当前时间跨度周期平移参考时间
    func shiftReferenceDate(by value: Int, range: StatisticsRange) {
        let component: Calendar.Component
        switch range {
        case .today: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        case .all: return
        }

        if let newDate = calendar.date(byAdding: component, value: value, to: referenceDate) {
            referenceDate = newDate
        }
    }

    // MARK: - Private Helpers

    private func updatePaginationState(range: StatisticsRange, now: Date) {
        // 1. 判断是否能够向前翻页。如果我们在最前没有数据的阶段，或者使用“全部”范围，则禁用。
        if range == .all {
            canShowPreviousPeriod = false
            canShowNextPeriod = false
            return
        }

        // 2. 检查是否有上一周期日志。这里可以通过 previousRangeLogs 是否有数据或之前是否有基础数据来确定。
        // 为了获得良好的体验，如果上一周期有数据记录，或者存在更早的历史数据，设为可向前翻页。
        canShowPreviousPeriod = !previousRangeLogs.isEmpty || baseRangeLogs.contains { $0.startTime < (interval(for: range, referenceDate: referenceDate, currentDate: now)?.start ?? Date()) }

        // 3. 判断是否能够向后翻页（不能越过当前周期的截止点）。
        guard let current = interval(for: range, referenceDate: referenceDate, currentDate: now),
              let latest = interval(for: range, referenceDate: now, currentDate: now) else {
            canShowNextPeriod = false
            return
        }
        canShowNextPeriod = current.start < latest.start
    }

    private func fetchLogs(for range: StatisticsRange, referenceDate: Date, modelContext: ModelContext) -> [ActivityLog] {
        let now = Date()
        guard let current = interval(for: range, referenceDate: referenceDate, currentDate: now) else {
            // 抓取全部日志数据
            let sortBy = [SortDescriptor(\ActivityLog.startTime, order: .reverse)]
            do {
                return try modelContext.fetch(FetchDescriptor<ActivityLog>(sortBy: sortBy))
            } catch {
                print("[StatisticsEngine] 抓取全部日志失败: \(error.localizedDescription)")
                return []
            }
        }

        // 为了进行同比对比计算，我们需要抓取当前周期和前一周期两个区间的连续日志。
        let start: Date
        if let prev = previousInterval(for: range, currentInterval: current) {
            start = prev.start
        } else {
            start = current.start
        }
        let end = current.end

        let descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { log in
                log.startTime >= start && log.startTime < end
            },
            sortBy: [SortDescriptor(\ActivityLog.startTime, order: .reverse)]
        )

        do {
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

    // MARK: - Date Intervals Calculations

    func interval(for range: StatisticsRange, referenceDate: Date, currentDate: Date) -> DateInterval? {
        let startOfRef = calendar.startOfDay(for: referenceDate)

        switch range {
        case .today:
            let start = startOfRef
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? currentDate
            let isCurrent = calendar.isDate(referenceDate, inSameDayAs: currentDate)
            let cappedEnd = isCurrent ? min(end, currentDate) : end
            return DateInterval(start: start, end: max(start, cappedEnd))

        case .week:
            guard let naturalInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return nil }
            let isCurrent = naturalInterval.contains(currentDate) || naturalInterval.start >= currentDate
            let cappedEnd = isCurrent ? min(naturalInterval.end, currentDate) : naturalInterval.end
            return DateInterval(start: naturalInterval.start, end: max(naturalInterval.start, cappedEnd))

        case .month:
            guard let naturalInterval = calendar.dateInterval(of: .month, for: referenceDate) else { return nil }
            let isCurrent = naturalInterval.contains(currentDate) || naturalInterval.start >= currentDate
            let cappedEnd = isCurrent ? min(naturalInterval.end, currentDate) : naturalInterval.end
            return DateInterval(start: naturalInterval.start, end: max(naturalInterval.start, cappedEnd))

        case .year:
            guard let naturalInterval = calendar.dateInterval(of: .year, for: referenceDate) else { return nil }
            let isCurrent = naturalInterval.contains(currentDate) || naturalInterval.start >= currentDate
            let cappedEnd = isCurrent ? min(naturalInterval.end, currentDate) : naturalInterval.end
            return DateInterval(start: naturalInterval.start, end: max(naturalInterval.start, cappedEnd))

        case .all:
            return nil
        }
    }

    func previousInterval(for range: StatisticsRange, currentInterval: DateInterval) -> DateInterval? {
        switch range {
        case .today:
            guard let prevStart = calendar.date(byAdding: .day, value: -1, to: currentInterval.start),
                  let prevEnd = calendar.date(byAdding: .day, value: -1, to: currentInterval.end) else { return nil }
            return DateInterval(start: prevStart, end: prevEnd)

        case .week:
            guard let prevStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentInterval.start),
                  let prevEnd = calendar.date(byAdding: .weekOfYear, value: -1, to: currentInterval.end) else { return nil }
            return DateInterval(start: prevStart, end: prevEnd)

        case .month:
            guard let prevStart = calendar.date(byAdding: .month, value: -1, to: currentInterval.start),
                  let prevEnd = calendar.date(byAdding: .month, value: -1, to: currentInterval.end) else { return nil }
            return DateInterval(start: prevStart, end: prevEnd)

        case .year:
            guard let prevStart = calendar.date(byAdding: .year, value: -1, to: currentInterval.start),
                  let prevEnd = calendar.date(byAdding: .year, value: -1, to: currentInterval.end) else { return nil }
            return DateInterval(start: prevStart, end: prevEnd)

        case .all:
            return nil
        }
    }

    // MARK: - Thread-Safe Static Logic (Background Processing)

    nonisolated private static func applyCriteria(to logs: [PreparedLog], using filters: FilterCriteria) -> [PreparedLog] {
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

    nonisolated private static func dailySummaries(for logs: [PreparedLog], studyLogs: [PreparedLog]) -> [DaySummary] {
        let allDays = Set(logs.map { $0.dayStart })
        let studyGrouped = Dictionary(grouping: studyLogs) { $0.dayStart }
        return allDays.map { date in
            let dayStudyLogs = studyGrouped[date] ?? []
            let studyDuration = dayStudyLogs.reduce(0) { $0 + $1.duration }
            return DaySummary(date: date, totalTime: studyDuration)
        }
        .sorted { $0.date < $1.date }
    }

    nonisolated private static func rankingEntries(for logs: [PreparedLog], dimension: RankingDimension) -> [RankingEntry] {
        let grouped = Dictionary(grouping: logs) { log in
            rankingKey(for: log, dimension: dimension)
        }
        return grouped.compactMap { key, groupedLogs in
            guard let key else { return nil }
            let displayName: String
            if dimension == .item, groupedLogs.first?.isPDF == true {
                // 如果是 PDF 且按单项展示，将唯一标识符映射回最近一次的文件名
                displayName = groupedLogs.max(by: { $0.startTime < $1.startTime })?.windowTitle ?? key
            } else {
                displayName = key
            }
            return RankingEntry(name: displayName, totalTime: groupedLogs.reduce(0) { $0 + $1.duration })
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
                let displayName: String
                if dimension == .app, detailLogs.first?.isPDF == true {
                    // 如果是在“预览”应用下展示其打开过的 PDF 文件列表，将指纹键映射回最新的文件名
                    displayName = detailLogs.max(by: { $0.startTime < $1.startTime })?.windowTitle ?? detailKey
                } else {
                    displayName = detailKey
                }
                return SummaryDetail(name: displayName, subtitle: detailSubtitle(for: detailLogs, dimension: dimension), totalTime: detailLogs.reduce(0) { $0 + $1.duration })
            }
            .sorted { $0.totalTime > $1.totalTime }
            
            let displayGroupName: String
            if dimension == .item, groupedLogs.first?.isPDF == true {
                // 单项维度（Item）排行下的 PDF 显示最新文件名
                displayGroupName = groupedLogs.max(by: { $0.startTime < $1.startTime })?.windowTitle ?? key
            } else {
                displayGroupName = key
            }
            return GroupedSummary(name: displayGroupName, totalTime: groupedLogs.reduce(0) { $0 + $1.duration }, details: details)
        }
        .sorted { $0.totalTime > $1.totalTime }
    }

    nonisolated private static func pdfSummaries(for logs: [PreparedLog]) -> [GroupedSummary] {
        let pdfLogs = logs.filter(\.isPDF)
        // 使用 pdfIdentifier 作为唯一合并键，不存在特征码的传统数据退回到 windowTitle
        let grouped = Dictionary(grouping: pdfLogs) { $0.pdfIdentifier ?? $0.windowTitle }
        return grouped.map { key, titleLogs in
            let latestTitle = titleLogs.max(by: { $0.startTime < $1.startTime })?.windowTitle ?? key
            return GroupedSummary(
                name: latestTitle,
                totalTime: titleLogs.reduce(0) { $0 + $1.duration },
                details: [SummaryDetail(name: latestTitle, subtitle: titleLogs.first?.appName, totalTime: titleLogs.reduce(0) { $0 + $1.duration })]
            )
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
        !log.isStudy
    }

    nonisolated private static func rankingKey(for log: PreparedLog, dimension: RankingDimension) -> String? {
        switch dimension {
        case .app: return log.appName
        case .domain: return log.resolvedDomain
        case .item:
            // 如果是 PDF，我们使用唯一指纹作为排行的汇总键，合并同文件重命名产生的多项记录
            if log.isPDF {
                return log.pdfIdentifier ?? log.windowTitle
            }
            return log.windowTitle
        }
    }

    nonisolated private static func detailKey(for log: PreparedLog, dimension: RankingDimension) -> String {
        switch dimension {
        case .app:
            // 预览 App 下展示 PDF 文档明细时，同样以唯一指纹作为合并键
            if log.isPDF {
                return log.pdfIdentifier ?? log.windowTitle
            }
            return log.windowTitle
        case .domain: return log.resolvedDomain ?? log.appName
        case .item: return log.resolvedDomain ?? log.appName
        }
    }

    nonisolated private static func detailSubtitle(for logs: [PreparedLog], dimension: RankingDimension) -> String? {
        guard dimension == .item else { return nil }
        let sources = Set(logs.map { $0.resolvedDomain ?? $0.appName }).sorted()
        return sources.isEmpty ? nil : sources.joined(separator: " · ")
    }

    nonisolated private static func longestStreak(in daySummaries: [DaySummary], calendar: Calendar) -> Int {
        guard !daySummaries.isEmpty else { return 0 }
        
        // 1. 提取所有活跃日期并进行升序排序。
        let sortedDays = daySummaries.map(\.date).sorted()
        var longest = 1
        var current = 1
        
        // 2. 遍历日期数组，判断相邻日期是否连续（相差一天）。
        for index in 1..<sortedDays.count {
            guard let previous = calendar.date(byAdding: .day, value: 1, to: sortedDays[index - 1]) else { continue }
            
            // 3. 若连续则递增当前计数并更新最大连续天数；若中断则重置当前计数。
            if calendar.isDate(previous, inSameDayAs: sortedDays[index]) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    nonisolated private static func strongestTimeSlot(in logs: [PreparedLog], calendar: Calendar) -> ReportTimeSlot? {
        guard !logs.isEmpty else { return nil }
        
        // 1. 将日志按开始时间分配到对应的时段桶（上午/下午/晚上/深夜）。
        var buckets: [ReportTimeSlot: TimeInterval] = [:]
        for log in logs {
            let hour = calendar.component(.hour, from: log.startTime)
            let slot: ReportTimeSlot
            switch hour {
            case 6..<12: slot = .morning
            case 12..<18: slot = .afternoon
            case 18..<24: slot = .evening
            default: slot = .lateNight
            }
            buckets[slot, default: 0] += log.duration
        }
        
        // 2. 找出累计时长最高的时段并返回。
        return buckets.max(by: { $0.value < $1.value })?.key
    }

    nonisolated private static func earliestStudyStart(in logs: [PreparedLog], calendar: Calendar) -> Date? {
        logs.min { lhs, rhs in
            minutesSinceStartOfDay(for: lhs.startTime, calendar: calendar) < minutesSinceStartOfDay(for: rhs.startTime, calendar: calendar)
        }?.startTime
    }

    nonisolated private static func latestStudyEnd(in logs: [PreparedLog], calendar: Calendar) -> Date? {
        logs.max { lhs, rhs in
            minutesSinceStartOfDay(for: lhs.endTime, calendar: calendar) < minutesSinceStartOfDay(for: rhs.endTime, calendar: calendar)
        }?.endTime
    }

    nonisolated private static func minutesSinceStartOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    nonisolated private static func buildComparison(currentLogs: [PreparedLog], previousLogs: [PreparedLog]) -> ReportComparison? {
        guard !previousLogs.isEmpty else { return nil }
        let currentTotal = currentLogs.reduce(0) { $0 + $1.duration }
        let previousTotal = previousLogs.reduce(0) { $0 + $1.duration }
        let currentActiveDays = Set(currentLogs.map(\.dayStart)).count
        let previousActiveDays = Set(previousLogs.map(\.dayStart)).count
        let rate: Double? = previousTotal > 0 ? (currentTotal - previousTotal) / previousTotal : nil
        return ReportComparison(
            totalDurationDelta: currentTotal - previousTotal,
            totalDurationChangeRate: rate,
            activeDaysDelta: currentActiveDays - previousActiveDays
        )
    }
}

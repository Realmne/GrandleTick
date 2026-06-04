import Foundation

enum ReportBuilder {
    static func build(
        period: ReportPeriod,
        logs: [ActivityLog],
        whitelist: WhitelistManager,
        referenceDate: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReportSnapshot {
        let whitelistSnapshot = ReportWhitelistSnapshot(whitelist: whitelist)
        let preparedLogs = logs.compactMap { ReportPreparedLog(log: $0, whitelist: whitelistSnapshot, calendar: calendar) }
        let naturalInterval = period.reportInterval(containing: referenceDate ?? now, currentDate: now, calendar: calendar)

        let currentLogs = preparedLogs.filter { naturalInterval.contains($0.startTime) }
        let interval = adjustedInterval(
            from: naturalInterval,
            period: period,
            currentLogs: currentLogs,
            calendar: calendar
        )
        let previousInterval = period.previousInterval(before: interval, calendar: calendar)
        let previousLogs = previousInterval.map { previous in
            preparedLogs.filter { previous.contains($0.startTime) }
        } ?? []
        let currentStudyLogs = currentLogs.filter { !isEntertainmentLog($0) }
        let previousStudyLogs = previousLogs.filter { !isEntertainmentLog($0) }
        let currentEntertainmentLogs = currentLogs.filter(isEntertainmentLog)

        let totalDuration = currentStudyLogs.reduce(0) { $0 + $1.duration }
        let entertainmentDuration = currentEntertainmentLogs.reduce(0) { $0 + $1.duration }
        let dayStats = dailyStats(for: currentStudyLogs, calendar: calendar)
        let completedDayStats = completedDayStats(from: dayStats, now: now, calendar: calendar)
        let activeDays = dayStats.count
        let averageDailyDuration = activeDays > 0 ? totalDuration / Double(activeDays) : 0
        let strongestDay = completedDayStats.max(by: { $0.totalTime < $1.totalTime })
        let shortestActiveDay = completedDayStats.min(by: { $0.totalTime < $1.totalTime })
        let longestStreak = longestStreak(in: dayStats, calendar: calendar)
        let topApps = rank(currentStudyLogs, by: .app, totalDuration: totalDuration)
        let topDomains = rank(currentStudyLogs, by: .domain, totalDuration: totalDuration)
        let topItems = rank(currentStudyLogs, by: .item, totalDuration: totalDuration)
        let topPDFs = rank(currentStudyLogs, by: .pdf, totalDuration: totalDuration)
        let websiteDuration = currentStudyLogs.filter(\.isWebsite).reduce(0) { $0 + $1.duration }
        let pdfDuration = currentStudyLogs.filter(\.isPDF).reduce(0) { $0 + $1.duration }
        let primaryTimeSlot = strongestTimeSlot(in: currentStudyLogs, calendar: calendar)
        let earliestStudyStart = earliestStudyStart(in: currentStudyLogs, calendar: calendar)
        let latestStudyEnd = latestStudyEnd(in: currentStudyLogs, calendar: calendar)
        let trendGranularity: ReportTrendGranularity = period == .year ? .month : .day
        let trendPoints = trendPoints(for: currentStudyLogs, period: period, interval: interval, calendar: calendar)
        let comparison = buildComparison(currentLogs: currentStudyLogs, previousLogs: previousStudyLogs)
        let coverSummary = buildCoverSummary(period: period, comparison: comparison)
        let appFocusSummary = buildAppFocusSummary(
            topApps: topApps,
            topDomains: topDomains,
            pdfDuration: pdfDuration,
            websiteDuration: websiteDuration
        )
        let summaryLines = buildSummaryLines(
            period: period,
            topApps: topApps,
            topDomains: topDomains,
            topPDFs: topPDFs,
            pdfDuration: pdfDuration,
            websiteDuration: websiteDuration,
            primaryTimeSlot: primaryTimeSlot,
            comparison: comparison
        )

        return ReportSnapshot(
            period: period,
            interval: interval,
            previousInterval: previousInterval,
            totalDuration: totalDuration,
            entertainmentDuration: entertainmentDuration,
            activeDays: activeDays,
            averageDailyDuration: averageDailyDuration,
            strongestDay: strongestDay,
            shortestActiveDay: shortestActiveDay,
            longestStreak: longestStreak,
            topApps: topApps,
            topDomains: topDomains,
            topItems: topItems,
            topPDFs: topPDFs,
            trendGranularity: trendGranularity,
            trendPoints: trendPoints,
            websiteDuration: websiteDuration,
            pdfDuration: pdfDuration,
            primaryTimeSlot: primaryTimeSlot,
            earliestStudyStart: earliestStudyStart,
            latestStudyEnd: latestStudyEnd,
            comparison: comparison,
            coverSummary: coverSummary,
            appFocusSummary: appFocusSummary,
            summaryLines: summaryLines
        )
    }

    private static func adjustedInterval(
        from interval: DateInterval,
        period: ReportPeriod,
        currentLogs: [ReportPreparedLog],
        calendar: Calendar
    ) -> DateInterval {
        guard period == .year, let firstLog = currentLogs.min(by: { $0.startTime < $1.startTime }) else {
            return interval
        }

        let adjustedStart = monthStart(for: firstLog.startTime, calendar: calendar)
        return DateInterval(start: adjustedStart, end: interval.end)
    }

    private static func buildComparison(currentLogs: [ReportPreparedLog], previousLogs: [ReportPreparedLog]) -> ReportComparison? {
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

    private static func buildCoverSummary(period: ReportPeriod, comparison: ReportComparison?) -> String {
        guard let comparison else {
            return "这是你的第一份\(period.title)回顾"
        }

        let delta = comparison.totalDurationDelta
        guard delta != 0 else {
            return "和\(period.previousTitle)相比，整体时长基本持平"
        }

        let direction = delta > 0 ? "多" : "少"
        let detail = delta > 0 ? "多了" : "少了"

        if let rate = comparison.totalDurationChangeRate {
            return "比\(period.previousTitle)\(direction) \(formatChangeRate(rate))，\(detail) \(formatCompactDuration(abs(delta)))"
        }

        return "比\(period.previousTitle)\(detail) \(formatCompactDuration(abs(delta)))"
    }

    private static func buildAppFocusSummary(
        topApps: [ReportRankItem],
        topDomains: [ReportRankItem],
        pdfDuration: TimeInterval,
        websiteDuration: TimeInterval
    ) -> String {
        if pdfDuration > 0, pdfDuration >= websiteDuration {
            return "这段时间你主要在看 PDF"
        }

        if let topDomain = topDomains.first {
            return "你花得最多的时间集中在 \(topDomain.name)"
        }

        if let topApp = topApps.first {
            return "你花得最多的时间集中在 \(topApp.name)"
        }

        return "这段时间的使用重心还不够明显"
    }

    private static func buildSummaryLines(
        period: ReportPeriod,
        topApps: [ReportRankItem],
        topDomains: [ReportRankItem],
        topPDFs: [ReportRankItem],
        pdfDuration: TimeInterval,
        websiteDuration: TimeInterval,
        primaryTimeSlot: ReportTimeSlot?,
        comparison: ReportComparison?
    ) -> [String] {
        var lines: [String] = []

        if pdfDuration > websiteDuration, pdfDuration > 0 {
            lines.append("这段时间你主要在看 PDF。")
        } else if let topDomain = topDomains.first {
            lines.append("你的主要时间花在了 \(topDomain.name)。")
        } else if let topApp = topApps.first {
            lines.append("你花时间最多的应用是 \(topApp.name)。")
        }

        if let topApp = topApps.first, let topDomain = topDomains.first {
            lines.append("使用重心主要集中在 \(topApp.name) 和 \(topDomain.name)。")
        } else if let topPDF = topPDFs.first {
            lines.append("花时间最多的具体内容是 \(topPDF.name)。")
        } else if let primaryTimeSlot {
            lines.append("你更常在\(primaryTimeSlot.title)进入状态。")
        }

        if let comparison {
            let delta = comparison.totalDurationDelta
            if delta > 0 {
                if let rate = comparison.totalDurationChangeRate {
                    lines.append("和\(period.previousTitle)比，你多了 \(formatChangeRate(rate))，约 \(formatCompactDuration(delta))。")
                } else {
                    lines.append("和\(period.previousTitle)比，你多了 \(formatCompactDuration(delta))。")
                }
            } else if delta < 0 {
                if let rate = comparison.totalDurationChangeRate {
                    lines.append("和\(period.previousTitle)比，你少了 \(formatChangeRate(rate))，约 \(formatCompactDuration(abs(delta)))。")
                } else {
                    lines.append("和\(period.previousTitle)比，你少了 \(formatCompactDuration(abs(delta)))。")
                }
            } else {
                lines.append("和\(period.previousTitle)比，整体时长基本持平。")
            }
        } else {
            lines.append("再积累一段时间，就能看到和\(period.previousTitle)的变化了。")
        }

        while lines.count < 3 {
            lines.append("记录再多一点，这里的回顾会更完整。")
        }

        return Array(lines.prefix(3))
    }

    private static func dailyStats(for logs: [ReportPreparedLog], calendar: Calendar) -> [ReportDayStat] {
        Dictionary(grouping: logs, by: \.dayStart)
            .map { date, groupedLogs in
                ReportDayStat(date: date, totalTime: groupedLogs.reduce(0) { $0 + $1.duration })
            }
            .sorted { $0.date < $1.date }
    }

    private static func completedDayStats(
        from dayStats: [ReportDayStat],
        now: Date,
        calendar: Calendar
    ) -> [ReportDayStat] {
        let todayStart = calendar.startOfDay(for: now)
        return dayStats.filter { $0.date < todayStart }
    }

    private static func earliestStudyStart(in logs: [ReportPreparedLog], calendar: Calendar) -> Date? {
        logs.min { lhs, rhs in
            minutesSinceStartOfDay(for: lhs.startTime, calendar: calendar) < minutesSinceStartOfDay(for: rhs.startTime, calendar: calendar)
        }?.startTime
    }

    private static func latestStudyEnd(in logs: [ReportPreparedLog], calendar: Calendar) -> Date? {
        logs.max { lhs, rhs in
            minutesSinceStartOfDay(for: lhs.endTime, calendar: calendar) < minutesSinceStartOfDay(for: rhs.endTime, calendar: calendar)
        }?.endTime
    }

    private static func longestStreak(in dayStats: [ReportDayStat], calendar: Calendar) -> Int {
        guard !dayStats.isEmpty else { return 0 }

        let sortedDays = dayStats.map(\.date).sorted()
        var longest = 1
        var current = 1

        for index in 1..<sortedDays.count {
            guard let previous = calendar.date(byAdding: .day, value: 1, to: sortedDays[index - 1]) else {
                continue
            }

            if calendar.isDate(previous, inSameDayAs: sortedDays[index]) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }

        return longest
    }

    private static func strongestTimeSlot(in logs: [ReportPreparedLog], calendar: Calendar) -> ReportTimeSlot? {
        guard !logs.isEmpty else { return nil }

        var buckets: [ReportTimeSlot: TimeInterval] = [:]
        for log in logs {
            let hour = calendar.component(.hour, from: log.startTime)
            let slot: ReportTimeSlot
            switch hour {
            case 6..<12:
                slot = .morning
            case 12..<18:
                slot = .afternoon
            case 18..<24:
                slot = .evening
            default:
                slot = .lateNight
            }
            buckets[slot, default: 0] += log.duration
        }

        return buckets.max(by: { $0.value < $1.value })?.key
    }

    private static func trendPoints(
        for logs: [ReportPreparedLog],
        period: ReportPeriod,
        interval: DateInterval,
        calendar: Calendar
    ) -> [ReportTrendPoint] {
        switch period {
        case .year:
            let grouped = Dictionary(grouping: logs) { log in
                monthStart(for: log.startTime, calendar: calendar)
            }
            let monthStarts = monthStarts(in: interval, calendar: calendar)
            return monthStarts.map { monthStart in
                ReportTrendPoint(
                    date: monthStart,
                    totalTime: (grouped[monthStart] ?? []).reduce(0) { $0 + $1.duration }
                )
            }
        case .week, .month:
            let grouped = Dictionary(grouping: logs, by: \.dayStart)
            let dayStarts = dayStarts(in: interval, calendar: calendar)
            return dayStarts.map { dayStart in
                ReportTrendPoint(
                    date: dayStart,
                    totalTime: (grouped[dayStart] ?? []).reduce(0) { $0 + $1.duration }
                )
            }
        }
    }

    private static func dayStarts(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var current = calendar.startOfDay(for: interval.start)

        while current < interval.end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }

        return dates
    }

    private static func monthStarts(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var current = monthStart(for: interval.start, calendar: calendar)

        while current < interval.end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else {
                break
            }
            current = next
        }

        return dates
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private static func rank(_ logs: [ReportPreparedLog], by dimension: ReportRankingDimension, totalDuration: TimeInterval) -> [ReportRankItem] {
        guard totalDuration > 0 else { return [] }

        let grouped = Dictionary(grouping: logs) { log in
            rankingKey(for: log, dimension: dimension)
        }

        return grouped.compactMap { key, groupedLogs in
            guard let key else { return nil }
            let itemTotal = groupedLogs.reduce(0) { $0 + $1.duration }
            return ReportRankItem(
                name: key,
                totalTime: itemTotal,
                share: itemTotal / totalDuration
            )
        }
        .sorted {
            if $0.totalTime == $1.totalTime {
                return $0.name < $1.name
            }
            return $0.totalTime > $1.totalTime
        }
        .prefix(3)
        .map { $0 }
    }

    private static func rankingKey(for log: ReportPreparedLog, dimension: ReportRankingDimension) -> String? {
        switch dimension {
        case .app:
            return log.appName
        case .domain:
            return log.resolvedDomain
        case .item:
            return log.windowTitle
        case .pdf:
            return log.isPDF ? log.windowTitle : nil
        }
    }

    private static func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let roundedSeconds = max(0, Int(seconds.rounded()))
        let hours = roundedSeconds / 3600
        let minutes = (roundedSeconds % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        return "\(max(minutes, 1)) 分钟"
    }

    private static func formatChangeRate(_ rate: Double) -> String {
        "\(Int((abs(rate) * 100).rounded()))%"
    }

    private static func isEntertainmentLog(_ log: ReportPreparedLog) -> Bool {
        log.resolvedDomain == "bilibili.com" && log.windowTitle == "娱乐"
    }

    private static func minutesSinceStartOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private enum ReportRankingDimension {
    case app
    case domain
    case item
    case pdf
}

private struct ReportWhitelistSnapshot {
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

private struct ReportPreparedLog {
    let appName: String
    let windowTitle: String
    let startTime: Date
    let dayStart: Date
    let duration: TimeInterval
    let resolvedDomain: String?
    let isPDF: Bool
    let isWebsite: Bool

    var endTime: Date {
        startTime.addingTimeInterval(duration)
    }

    init?(log: ActivityLog, whitelist: ReportWhitelistSnapshot, calendar: Calendar) {
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

        self.appName = log.appName
        self.windowTitle = log.windowTitle
        self.startTime = log.startTime
        self.dayStart = calendar.startOfDay(for: log.startTime)
        self.duration = log.duration
        self.resolvedDomain = resolvedDomain
        self.isPDF = Self.isPDF(log)
        self.isWebsite = isWebsite
    }

    private static func resolveDomain(for log: ActivityLog, whitelist: ReportWhitelistSnapshot) -> String? {
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

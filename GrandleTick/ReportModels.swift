import Foundation

enum ReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "本年"
        }
    }

    var reportTitle: String {
        switch self {
        case .week: return "本周学习回顾"
        case .month: return "本月学习回顾"
        case .year: return "本年学习回顾"
        }
    }

    var previousTitle: String {
        switch self {
        case .week: return "上周"
        case .month: return "上月"
        case .year: return "去年"
        }
    }

    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        reportInterval(containing: date, currentDate: date, calendar: calendar)
    }

    func reportInterval(containing date: Date, currentDate: Date, calendar: Calendar) -> DateInterval {
        // 1. 先取得参考日期所在的自然周、月或年区间。
        let naturalInterval: DateInterval

        switch self {
        case .week:
            naturalInterval = calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 24 * 3600)
        case .month:
            naturalInterval = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 30 * 24 * 3600)
        case .year:
            naturalInterval = calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 365 * 24 * 3600)
        }

        // 2. 判断参考日期是否落在当前周期或未来周期，用于决定是否截断结束时间。
        let currentNaturalInterval = naturalDateInterval(for: currentDate, calendar: calendar)
        let shouldCapToCurrentDate = naturalInterval.start >= currentNaturalInterval.start

        // 3. 历史周期展示完整区间，当前周期只展示到当前时间，避免包含未来日期。
        let cappedEnd = shouldCapToCurrentDate ? min(naturalInterval.end, currentDate) : naturalInterval.end
        return DateInterval(start: naturalInterval.start, end: max(naturalInterval.start, cappedEnd))
    }

    private func naturalDateInterval(for date: Date, calendar: Calendar) -> DateInterval {
        switch self {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 24 * 3600)
        case .month:
            return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 30 * 24 * 3600)
        case .year:
            return calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 365 * 24 * 3600)
        }
    }

    func previousInterval(before interval: DateInterval, calendar: Calendar) -> DateInterval? {
        switch self {
        case .week:
            guard
                let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.start),
                let previousEnd = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.end)
            else {
                return nil
            }
            return DateInterval(start: previousStart, end: previousEnd)
        case .month:
            guard
                let previousStart = calendar.date(byAdding: .month, value: -1, to: interval.start),
                let previousEnd = calendar.date(byAdding: .month, value: -1, to: interval.end)
            else {
                return nil
            }
            return DateInterval(start: previousStart, end: previousEnd)
        case .year:
            guard
                let previousStart = calendar.date(byAdding: .year, value: -1, to: interval.start),
                let previousEnd = calendar.date(byAdding: .year, value: -1, to: interval.end)
            else {
                return nil
            }
            return DateInterval(start: previousStart, end: previousEnd)
        }
    }
}

struct ReportSnapshot: Sendable {
    let period: ReportPeriod
    let interval: DateInterval
    let previousInterval: DateInterval?
    let totalDuration: TimeInterval
    let entertainmentDuration: TimeInterval
    let activeDays: Int
    let averageDailyDuration: TimeInterval
    let strongestDay: ReportDayStat?
    let shortestActiveDay: ReportDayStat?
    let longestStreak: Int
    let topApps: [ReportRankItem]
    let topDomains: [ReportRankItem]
    let topItems: [ReportRankItem]
    let topPDFs: [ReportRankItem]
    let trendGranularity: ReportTrendGranularity
    let trendPoints: [ReportTrendPoint]
    let websiteDuration: TimeInterval
    let pdfDuration: TimeInterval
    let primaryTimeSlot: ReportTimeSlot?
    let earliestStudyStart: Date?
    let latestStudyEnd: Date?
    let comparison: ReportComparison?
    let coverSummary: String
    let appFocusSummary: String
    let summaryLines: [String]

    var hasData: Bool {
        totalDuration > 0
    }
}

struct ReportRankItem: Identifiable, Sendable {
    let name: String
    let totalTime: TimeInterval
    let share: Double

    var id: String { name }
}

struct ReportDayStat: Identifiable, Sendable {
    let date: Date
    let totalTime: TimeInterval

    var id: Date { date }
}

enum ReportTrendGranularity: Sendable {
    case day
    case month
}

struct ReportTrendPoint: Identifiable, Sendable {
    let date: Date
    let totalTime: TimeInterval

    var id: Date { date }
}

struct ReportComparison: Sendable {
    let totalDurationDelta: TimeInterval
    let totalDurationChangeRate: Double?
    let activeDaysDelta: Int
}

enum ReportTimeSlot: String, Sendable {
    case morning
    case afternoon
    case evening
    case lateNight

    var title: String {
        switch self {
        case .morning: return "上午"
        case .afternoon: return "下午"
        case .evening: return "晚上"
        case .lateNight: return "深夜"
        }
    }
}

import Foundation

enum ReportPage: Int, CaseIterable, Identifiable, Sendable {
    case cover, appChampion, sources, peakDay, rhythm
    var id: Int { rawValue }
    var index: Int { rawValue }
    
    var label: String {
        switch self {
        case .cover: return "总览"
        case .appChampion: return "热度最高 App"
        case .sources: return "常看内容"
        case .peakDay: return "高峰日"
        case .rhythm: return "学习节奏"
        }
    }
}

enum ReportFormatter {
    static func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let roundedSeconds = max(0, Int(seconds.rounded()))
        let hours = roundedSeconds / 3600
        let minutes = (roundedSeconds % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分"
    }

    static func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let roundedSeconds = max(0, Int(seconds.rounded()))
        let hours = roundedSeconds / 3600
        let minutes = (roundedSeconds % 3600) / 60
        let remainingSeconds = roundedSeconds % 60
        return hours > 0
            ? String(format: "%02d小时%02d分%02d秒", hours, minutes, remainingSeconds)
            : String(format: "%02d分%02d秒", minutes, remainingSeconds)
    }

    static func formatShortDate(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    static func formatLongDate(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    static func formatDateRange(_ interval: DateInterval, calendar: Calendar = .current) -> String {
        let endDate = interval.end.addingTimeInterval(-1)
        return "\(formatShortDate(interval.start, calendar: calendar)) - \(formatShortDate(endDate, calendar: calendar))"
    }

    static func formatClock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

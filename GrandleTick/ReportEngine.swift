import Foundation
import SwiftData

@MainActor
@Observable
final class ReportEngine {
    var snapshot: ReportSnapshot?
    var canShowPreviousPeriod = false

    private let calendar = Calendar.current

    // 1. 构建当前报告快照。
    // 包含日志抓取、白名单过滤及复杂的聚合计算。
    func refreshSnapshot(
        period: ReportPeriod,
        referenceDate: Date,
        modelContext: ModelContext,
        whitelist: WhitelistManager
    ) {
        let now = Date()
        let logs = fetchLogsForPeriod(period: period, referenceDate: referenceDate, now: now, modelContext: modelContext)

        snapshot = ReportBuilder.build(
            period: period,
            logs: logs,
            whitelist: whitelist,
            referenceDate: referenceDate,
            now: now,
            calendar: calendar
        )

        canShowPreviousPeriod = checkHasDataInPreviousPeriod(
            period: period,
            referenceDate: referenceDate,
            now: now,
            modelContext: modelContext,
            whitelist: whitelist
        )
    }

    // 2. 检查前一个周期是否有可用的学习数据。
    // 用于决定 UI 上“上一期”按钮的启用状态。
    private func checkHasDataInPreviousPeriod(
        period: ReportPeriod,
        referenceDate: Date,
        now: Date,
        modelContext: ModelContext,
        whitelist: WhitelistManager
    ) -> Bool {
        guard let previousRefDate = calendar.date(byAdding: reportCalendarComponent(for: period), value: -1, to: referenceDate) else {
            return false
        }

        let interval = period.reportInterval(containing: previousRefDate, currentDate: now, calendar: calendar)
        let comparisonInterval = period.previousInterval(before: interval, calendar: calendar)
        let fetchStart = comparisonInterval?.start ?? interval.start

        let logs = fetchLogs(from: fetchStart, to: interval.end, modelContext: modelContext)
        let prevSnapshot = ReportBuilder.build(
            period: period,
            logs: logs,
            whitelist: whitelist,
            referenceDate: previousRefDate,
            now: now,
            calendar: calendar
        )

        return prevSnapshot.hasData
    }

    // 3. 按时间段抓取原始日志。
    private func fetchLogsForPeriod(period: ReportPeriod, referenceDate: Date, now: Date, modelContext: ModelContext) -> [ActivityLog] {
        let interval = period.reportInterval(containing: referenceDate, currentDate: now, calendar: calendar)
        let previousInterval = period.previousInterval(before: interval, calendar: calendar)
        let start = previousInterval?.start ?? interval.start

        return fetchLogs(from: start, to: interval.end, modelContext: modelContext)
    }

    private func fetchLogs(from start: Date, to end: Date, modelContext: ModelContext) -> [ActivityLog] {
        let descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { log in
                log.startTime >= start && log.startTime < end
            },
            sortBy: [SortDescriptor(\ActivityLog.startTime, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("[ReportEngine] 抓取日志失败: \(error.localizedDescription)")
            return []
        }
    }

    private func reportCalendarComponent(for period: ReportPeriod) -> Calendar.Component {
        switch period {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

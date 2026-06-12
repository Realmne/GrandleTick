import SwiftUI

struct ReportRhythmPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let formatDay: (Date) -> String
    let formatLongDay: (Date) -> String
    let formatClock: (Date) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                ReportMetricCard(title: "最长连续学习", value: "\(snapshot.longestStreak) 天", subtitle: "最长连续活跃区间", tint: .purple)
                ReportMetricCard(title: "活跃天数", value: "\(snapshot.activeDays) 天", subtitle: snapshot.period.title, tint: .green)
                ReportMetricCard(title: "主要时段", value: snapshot.primaryTimeSlot?.title ?? "暂无", subtitle: "按开始时间统计", tint: .orange)
            }
            
            HStack(spacing: 16) {
                ReportClockCard(
                    title: "最早开始",
                    value: snapshot.earliestStudyStart.map(formatClock) ?? "暂无",
                    subtitle: snapshot.earliestStudyStart.map(formatLongDay) ?? "暂无记录"
                )
                ReportClockCard(
                    title: "最晚结束",
                    value: snapshot.latestStudyEnd.map(formatClock) ?? "暂无",
                    subtitle: snapshot.latestStudyEnd.map(formatLongDay) ?? "暂无记录"
                )
            }
            
            HStack(alignment: .top, spacing: 18) {
                ReportDaySummaryCard(
                    title: "最长学习日",
                    stat: snapshot.strongestDay,
                    formatDuration: formatDuration,
                    formatDay: formatDay
                )
                
                ReportDaySummaryCard(
                    title: "最短学习日",
                    stat: snapshot.shortestActiveDay,
                    formatDuration: formatDuration,
                    formatDay: formatDay
                )
            }
        }
    }
}

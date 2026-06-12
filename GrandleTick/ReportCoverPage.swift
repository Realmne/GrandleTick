import SwiftUI

struct ReportCoverPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let formatDateRange: (DateInterval) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(formatDuration(snapshot.totalDuration)).font(.system(size: 50, weight: .bold, design: .rounded))
                    Text(snapshot.coverSummary).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                VStack(alignment: .leading, spacing: 12) {
                    ReportMiniBadge(title: "活跃天数", value: "\(snapshot.activeDays) 天")
                    ReportMiniBadge(title: "日均时长", value: formatDuration(snapshot.averageDailyDuration))
                }
            }
            .padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 30).fill(LinearGradient(colors: [Color(red: 0.90, green: 0.94, blue: 1.0), Color(red: 1.0, green: 0.96, blue: 0.90)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.7), lineWidth: 1))
            .fadeInSlide(delay: 0.0)

            HStack(spacing: 16) {
                ReportMetricCard(title: "活跃天数", value: "\(snapshot.activeDays) 天", subtitle: snapshot.period.title, tint: .green)
                    .fadeInSlide(delay: 0.1)
                ReportMetricCard(title: "日均学习", value: formatDuration(snapshot.averageDailyDuration), subtitle: "按活跃天计算", tint: .orange)
                    .fadeInSlide(delay: 0.15)
                ReportMetricCard(title: "记录范围", value: formatDateRange(snapshot.interval), subtitle: "截至今天", tint: .blue)
                    .fadeInSlide(delay: 0.2)
            }
            
            ReportBalanceDonutCard(studyDuration: snapshot.totalDuration, entertainmentDuration: snapshot.entertainmentDuration, formatDuration: formatDuration)
                .fadeInSlide(delay: 0.3)
        }
    }
}

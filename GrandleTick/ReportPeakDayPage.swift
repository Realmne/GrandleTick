import SwiftUI
import Charts

struct ReportPeakDayPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let formatDay: (Date) -> String
    
    @State private var animateData = false
    
    private var maxHours: Double {
        let peakHours = snapshot.trendPoints.map { $0.totalTime / 3600 }.max() ?? 0
        return peakHours <= 2 ? 2 : ceil(peakHours)
    }
    
    private var yAxisStride: Double {
        maxHours <= 4 ? 1 : 2
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(snapshot.trendGranularity == .month ? "月度趋势" : "每日趋势")
                .font(.headline)
            
            Chart(snapshot.trendPoints) { point in
                let value = animateData ? (point.totalTime / 3600) : 0.0
                BarMark(
                    x: .value("日期", axisLabel(for: point.date)),
                    y: .value("时长", value)
                )
                .foregroundStyle(Color.accentColor.opacity(0.65))
                .cornerRadius(4)
            }
            .frame(height: 280)
            .animation(.spring(response: 0.75, dampingFraction: 0.80), value: animateData)
            .chartXScale(domain: snapshot.trendPoints.map { axisLabel(for: $0.date) })
            .chartYScale(domain: 0 ... maxHours)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: yAxisStride)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text(hours == 0 ? "0小时" : hours.rounded(.towardZero) == hours ? "\(Int(hours))小时" : "\(hours.formatted(.number.precision(.fractionLength(1))))小时")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: snapshot.trendPoints.map { axisLabel(for: $0.date) }) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                        }
                    }
                }
            }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .fadeInSlide(delay: 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.80).delay(0.1)) {
                animateData = true
            }
        }
    }
    
    private func axisLabel(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return snapshot.trendGranularity == .day ? "\(components.month ?? 0)/\(components.day ?? 0)" : "\(components.month ?? 0)月"
    }
}

import SwiftUI
import Charts

struct ReportPeakDayPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    let formatDay: (Date) -> String
    
    @State private var animProgress: Double = 0.0
    
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
                // 1. 面积图渲染底部阴影渐变，营造空间感。
                AreaMark(
                    x: .value("日期", axisLabel(for: point.date)),
                    y: .value("时长", (point.totalTime / 3600) * animProgress)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                // 2. 折线图突出核心趋势起伏。
                LineMark(
                    x: .value("日期", axisLabel(for: point.date)),
                    y: .value("时长", (point.totalTime / 3600) * animProgress)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2.0))
                .interpolationMethod(.catmullRom)
                
                // 3. 柱状图展示具体每日分布，添加圆角。
                BarMark(
                    x: .value("日期", axisLabel(for: point.date)),
                    y: .value("时长", (point.totalTime / 3600) * animProgress)
                )
                .foregroundStyle(Color.accentColor.opacity(0.4).gradient)
                .cornerRadius(4)
            }
            .frame(height: 280)
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
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.72)))
        .fadeInSlide(delay: 0.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85)) {
                animProgress = 1.0
            }
        }
    }
    
    private func axisLabel(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return snapshot.trendGranularity == .day ? "\(components.month ?? 0)/\(components.day ?? 0)" : "\(components.month ?? 0)月"
    }
}

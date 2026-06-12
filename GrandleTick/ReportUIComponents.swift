import SwiftUI
import Charts

struct ReportMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(tint.opacity(0.20), lineWidth: 1))
    }
}

struct ReportBalanceCard: View {
    let studyDuration: TimeInterval
    let entertainmentDuration: TimeInterval
    let formatDuration: (TimeInterval) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("时间分布")
                .font(.headline)
            
            GeometryReader { geometry in
                let total = studyDuration + entertainmentDuration
                let ratio = total > 0 ? studyDuration / total : 1
                
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.blue.opacity(0.65))
                        .frame(width: max(geometry.size.width * ratio, studyDuration > 0 ? 24 : 0), height: 12)
                    
                    if entertainmentDuration > 0 {
                        Capsule()
                            .fill(Color.orange.opacity(0.55))
                            .frame(width: max(geometry.size.width * (1 - ratio), 20), height: 12)
                    }
                }
            }
            .frame(height: 12)
            
            HStack(spacing: 18) {
                ReportLegendStat(title: "学习时间", value: formatDuration(studyDuration), tint: .blue)
                ReportLegendStat(title: "娱乐时间", value: formatDuration(entertainmentDuration), tint: .orange)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

struct ReportHighlightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("热度最高 App")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28).fill(LinearGradient(colors: [tint.opacity(0.18), Color.white.opacity(0.70)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

struct ReportClockCard: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

struct ReportRankingPanel: View {
    let title: String
    let items: [ReportRankItem]
    let formatDuration: (TimeInterval) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            
            if items.isEmpty {
                Text("暂无数据")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(index + 1). \(item.name)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(formatDuration(item.totalTime))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(height: 10)
                                    
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: max(geometry.size.width * item.share, 10), height: 10)
                                }
                            }
                            .frame(height: 10)
                            
                            Text("占比 \(Int((item.share * 100).rounded()))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

struct ReportDaySummaryCard: View {
    let title: String
    let stat: ReportDayStat?
    let formatDuration: (TimeInterval) -> String
    let formatDay: (Date) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            if let stat {
                Text(formatDay(stat.date))
                    .font(.system(size: 22, weight: .bold))
                
                Text(formatDuration(stat.totalTime))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.secondary)
            } else {
                Text("暂无数据")
                    .foregroundColor(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

struct ReportPlaceholderCard: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
    }
}

struct ReportMiniBadge: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.56)))
    }
}

struct ReportPagerButton: View {
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(isDisabled ? 0.38 : 0.86))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isDisabled ? Color.white.opacity(0.34) : isPressed ? Color.white.opacity(0.96) : isHovered ? Color.white.opacity(0.90) : Color.white.opacity(0.72))
                )
                .overlay(
                    Circle()
                        .stroke(isDisabled ? Color.black.opacity(0.04) : Color.black.opacity(isHovered ? 0.10 : 0.07), lineWidth: 0.8)
                )
                .scaleEffect(isPressed && !isDisabled ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            if !isDisabled {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
        .pressing { pressing in
            if !isDisabled {
                withAnimation(.easeOut(duration: 0.08)) {
                    isPressed = pressing
                }
            }
        }
    }
}

extension View {
    func pressing(_ onPress: @escaping (Bool) -> Void) -> some View {
        buttonStyle(PressObserverStyle(onPress: onPress))
    }
}

struct PressObserverStyle: ButtonStyle {
    let onPress: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, isPressed in
            onPress(isPressed)
        }
    }
}

struct ReportLegendStat: View {
    let title: String
    let value: String
    let tint: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint.opacity(0.75))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        }
    }
}

// MARK: - New Interactive Chart Components & Animations

struct FadeInSlideModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: isVisible ? 0 : 18)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func fadeInSlide(delay: Double = 0.0) -> some View {
        modifier(FadeInSlideModifier(delay: delay))
    }
}

struct ReportBalanceDonutCard: View {
    let studyDuration: TimeInterval
    let entertainmentDuration: TimeInterval
    let formatDuration: (TimeInterval) -> String
    
    @State private var animProgress: Double = 0.0
    
    private var total: TimeInterval { studyDuration + entertainmentDuration }
    private var studyShare: Double { total > 0 ? studyDuration / total : 1.0 }
    
    struct Segment: Identifiable {
        let id = UUID()
        let type: String
        let duration: Double
        let color: Color
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("时间分布")
                .font(.headline)
            
            HStack(spacing: 24) {
                let data = [
                    Segment(type: "学习时间", duration: studyDuration * animProgress, color: .blue),
                    Segment(type: "娱乐时间", duration: entertainmentDuration * animProgress, color: .orange)
                ].filter { $0.duration > 0 }
                
                Chart(data) { segment in
                    SectorMark(
                        angle: .value("时间", segment.duration),
                        innerRadius: .ratio(0.62),
                        angularInset: 2.0
                    )
                    .cornerRadius(6)
                    .foregroundStyle(segment.color.gradient)
                }
                .frame(width: 140, height: 140)
                .chartBackground { chartProxy in
                    GeometryReader { geo in
                        if let frame = chartProxy.plotFrame {
                            let frameWidth = geo[frame].width
                            let frameHeight = geo[frame].height
                            VStack(spacing: 2) {
                                Text("学习占比")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("\(Int((studyShare * 100).rounded()))%")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.blue)
                            }
                            .position(x: frameWidth / 2, y: frameHeight / 2)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    ReportLegendStat(title: "学习时间", value: formatDuration(studyDuration), tint: .blue)
                    ReportLegendStat(title: "娱乐时间", value: formatDuration(entertainmentDuration), tint: .orange)
                }
                
                Spacer()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animProgress = 1.0
            }
        }
    }
}

struct ReportAppDistributionCard: View {
    let topApps: [ReportRankItem]
    let totalDuration: TimeInterval
    let formatDuration: (TimeInterval) -> String
    
    @State private var animProgress: Double = 0.0
    
    private let palette: [Color] = [.blue, .purple, .teal, .pink]
    
    struct Segment: Identifiable {
        let id = UUID()
        let name: String
        let duration: Double
        let color: Color
    }
    
    private var segments: [Segment] {
        var result: [Segment] = []
        var sumTop = 0.0
        
        for (index, item) in topApps.enumerated() {
            let color = palette[index % palette.count]
            result.append(Segment(name: item.name, duration: item.totalTime, color: color))
            sumTop += item.totalTime
        }
        
        let remaining = max(0, totalDuration - sumTop)
        if remaining > 60 {
            result.append(Segment(name: "其他应用", duration: remaining, color: .gray.opacity(0.4)))
        }
        
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("App 专注度分布")
                .font(.headline)
            
            let displaySegments = segments.map { Segment(name: $0.name, duration: $0.duration * animProgress, color: $0.color) }
            
            HStack(spacing: 20) {
                Chart(displaySegments) { segment in
                    SectorMark(
                        angle: .value("时长", segment.duration),
                        innerRadius: .ratio(0.60),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(segment.color.gradient)
                }
                .frame(width: 140, height: 140)
                
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(segments) { segment in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(segment.color.gradient)
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(segment.name)
                                    .font(.caption)
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineLimit(1)
                                Text(formatDuration(segment.duration))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) {
                animProgress = 1.0
            }
        }
    }
}

struct ReportContentCategoryCard: View {
    let websiteDuration: TimeInterval
    let pdfDuration: TimeInterval
    let totalDuration: TimeInterval
    let formatDuration: (TimeInterval) -> String
    
    @State private var animProgress: Double = 0.0
    
    struct Category: Identifiable {
        let id = UUID()
        let name: String
        let duration: Double
        let color: Color
    }
    
    private var categories: [Category] {
        let appDuration = max(0, totalDuration - websiteDuration - pdfDuration)
        return [
            Category(name: "PDF 文档", duration: pdfDuration, color: .purple),
            Category(name: "网页浏览", duration: websiteDuration, color: .teal),
            Category(name: "原生应用", duration: appDuration, color: .blue)
        ].filter { $0.duration > 0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("学习载体分布")
                .font(.headline)
            
            let displayCategories = categories.map { Category(name: $0.name, duration: $0.duration * animProgress, color: $0.color) }
            
            HStack(spacing: 24) {
                Chart(displayCategories) { item in
                    SectorMark(
                        angle: .value("时长", item.duration),
                        innerRadius: .ratio(0.60),
                        angularInset: 2.0
                    )
                    .cornerRadius(5)
                    .foregroundStyle(item.color.gradient)
                }
                .frame(width: 140, height: 140)
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(categories) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.color.gradient)
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.caption)
                                    .foregroundColor(.primary.opacity(0.85))
                                Text(formatDuration(item.duration))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animProgress = 1.0
            }
        }
    }
}

struct ReportRhythmHourlyChart: View {
    let hourlyDurations: [Double]
    
    @State private var animProgress: Double = 0.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("24小时专注度分布")
                .font(.headline)
            
            let chartData = hourlyDurations.enumerated().map { index, value in
                (hour: index, value: (value / 3600.0) * animProgress)
            }
            
            Chart {
                ForEach(chartData, id: \.hour) { item in
                    AreaMark(
                        x: .value("时间", "\(item.hour)点"),
                        y: .value("时长", item.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple.opacity(0.30), .purple.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                
                ForEach(chartData, id: \.hour) { item in
                    LineMark(
                        x: .value("时间", "\(item.hour)点"),
                        y: .value("时长", item.value)
                    )
                    .foregroundStyle(Color.purple.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: ["0点", "4点", "8点", "12点", "16点", "20点"]) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text(hours == 0 ? "0h" : String(format: "%.1fh", hours))
                        }
                    }
                }
            }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9)) {
                animProgress = 1.0
            }
        }
    }
}

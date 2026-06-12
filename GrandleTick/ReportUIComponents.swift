import SwiftUI

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

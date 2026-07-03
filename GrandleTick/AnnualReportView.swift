import SwiftUI
import SwiftData
import Charts

// MARK: - Annual Report View

struct AnnualReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 用于内部悬浮卡片模式的自定义关闭回调
    var dismissAction: (() -> Void)? = nil
    
    // 1. 年度报告跟随主应用的浅色信息卡风格，避免暗色报告与统计页整体视觉割裂。
    static let studyColor = Color(red: 0.12, green: 0.44, blue: 0.82)
    static let entertainmentColor = Color(red: 0.80, green: 0.32, blue: 0.58)
    static let websiteColor = Color(red: 0.06, green: 0.56, blue: 0.48)
    static let pdfColor = Color(red: 0.84, green: 0.45, blue: 0.12)
    static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.18)
    static let secondaryText = Color(red: 0.36, green: 0.40, blue: 0.48)
    static let tertiaryText = Color(red: 0.56, green: 0.60, blue: 0.68)
    static let cardFill = Color.white.opacity(0.82)
    static let softFill = Color(red: 0.95, green: 0.97, blue: 0.99)
    static let borderColor = Color.black.opacity(0.08)
    
    @State private var engine = StatisticsEngine()
    @State private var currentPage = 0
    @State private var isLoading = true
    @State private var appearAnimate = false
    @State private var reportYear = Calendar.current.component(.year, from: Date())
    
    private let totalPages = 8
    private let calendar = Calendar.current
    
    var body: some View {
        ZStack {
            // 1. 主卡片视图与导航控制。
            VStack(spacing: 20) {
                if isLoading {
                    loadingView
                } else {
                    mainCardDeck
                }
            }
            .frame(width: 480, height: 640)
            .background(
                LightReportBackground()
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(AnnualReportView.borderColor, lineWidth: 1)
                )
            )
            .shadow(color: Color.black.opacity(0.16), radius: 24, x: 0, y: 14)
            
            // 3. 右上角浮动关闭按钮。
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        if let dismissAction {
                            dismissAction()
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AnnualReportView.secondaryText.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(20)
                }
                Spacer()
            }
            .frame(width: 480, height: 640)
        }
        .frame(width: 480, height: 640)
        .onAppear {
            // 1. 加载本年度学习与娱乐的相关统计数据。
            loadYearlyData()
            
            // 2. 异步获取承载当前年度报告视图的 NSWindow，并将其底色和边框设为透明。
            // 解决 macOS 默认 Sheet 容器在圆角外侧留下的白色/灰色底色与方形框视觉 Bug。
            DispatchQueue.main.async {
                // 连续在多个时段尝试寻找并清理，防止生命周期回调时 NSWindow 尚未完全挂载到应用树上。
                for delay in [0.0, 0.05, 0.1, 0.15, 0.2] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        for window in NSApplication.shared.windows {
                            // 查找带有 Sheet 属性的窗口（即 sheetParent 非空，或者类名包含 Sheet 的窗口）
                            if window.sheetParent != nil || window.className.contains("Sheet") {
                                window.backgroundColor = .clear
                                window.isOpaque = false
                                window.hasShadow = true
                                window.invalidateShadow()
                                
                                // 同时也把其 contentView 的宿主 layer 设为透明，彻底防止 AppKit 默认白色背景重绘。
                                if let contentView = window.contentView {
                                    contentView.wantsLayer = true
                                    contentView.layer?.backgroundColor = NSColor.clear.cgColor
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
            
            Text("正在编排您的年度时光印记...")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AnnualReportView.secondaryText)
        }
    }
    
    private var mainCardDeck: some View {
        VStack(spacing: 0) {
            // 1. 内容切换卡片区，带过渡动画。
            ZStack {
                Group {
                    switch currentPage {
                    case 0:
                        CoverCard(year: reportYear, appear: appearAnimate)
                    case 1:
                        AnnualOverviewCard(
                            studyDuration: engine.studyDuration,
                            activeDays: engine.activeDays,
                            averageDailyDuration: engine.averageDailyDuration,
                            topAppSummary: engine.topAppSummary,
                            comparison: engine.comparison,
                            appear: appearAnimate
                        )
                    case 2:
                        FocusRatioCard(
                            studyDuration: engine.studyDuration,
                            entertainmentDuration: engine.entertainmentDuration,
                            appear: appearAnimate
                        )
                    case 3:
                        RhythmCard(
                            primarySlot: engine.primaryTimeSlot,
                            earliest: engine.earliestStudyStart,
                            latest: engine.latestStudyEnd,
                            hourlyDurations: engine.hourlyDurations,
                            appear: appearAnimate
                        )
                    case 4:
                        ContentMixCard(
                            websiteDuration: engine.websiteDuration,
                            pdfDuration: engine.pdfDuration,
                            topApps: engine.rankingEntries,
                            totalDuration: engine.rangeTotalDuration,
                            appear: appearAnimate
                        )
                    case 5:
                        CompanionCard(
                            topWebsites: engine.topWebsites,
                            topPDFs: engine.topPDFs,
                            appear: appearAnimate
                        )
                    case 6:
                        StreakCard(
                            longestStreak: engine.longestStreak,
                            strongestDay: engine.strongestDay,
                            shortestActiveDay: engine.shortestActiveDay,
                            activeDays: engine.activeDays,
                            appear: appearAnimate
                        )
                    case 7:
                        ArchetypeCard(
                            pdfDuration: engine.pdfDuration,
                            websiteDuration: engine.websiteDuration,
                            longestStreak: engine.longestStreak,
                            primarySlot: engine.primaryTimeSlot,
                            actionReset: { switchPage(to: 0) },
                            appear: appearAnimate
                        )
                    default:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            
            // 2. 底部翻页控制器与导航按钮。
            HStack {
                Button(action: { switchPage(to: currentPage - 1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(currentPage > 0 ? AnnualReportView.primaryText : AnnualReportView.tertiaryText.opacity(0.35))
                        .padding(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(currentPage == 0)
                
                Spacer()
                
                // 3. 点状页面指示器。
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? AnnualReportView.studyColor : AnnualReportView.borderColor)
                            .frame(width: index == currentPage ? 8 : 6, height: index == currentPage ? 8 : 6)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                
                Spacer()
                
                Button(action: { switchPage(to: currentPage + 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(currentPage < totalPages - 1 ? AnnualReportView.primaryText : AnnualReportView.tertiaryText.opacity(0.35))
                        .padding(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(currentPage == totalPages - 1)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - Private Logic
    
    private func loadYearlyData() {
        // 1. 获取当前系统时间，并提取今年年份作为报告的时间参考点。
        let now = Date()
        reportYear = calendar.component(.year, from: now)
        
        // 2. 将引擎的时间基准调整为当前日期，以便统计整年数据。
        engine.referenceDate = now
        
        // 3. 执行年度数据抓取并清洗，限制范围为 .year。
        engine.refreshBaseData(for: .year, modelContext: modelContext, whitelist: WhitelistManager.shared)
        
        // 4. 异步计算今年所有时间、排名、时段分布等指标。
        engine.applyFilters(
            searchText: "",
            contentFilter: .all,
            appFilter: nil,
            domainFilter: nil,
            dimension: .app,
            range: .year
        )
        
        // 5. 延迟 0.6 秒关闭加载状态以等待底层计算结果就绪，触发开场动画。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.isLoading = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                self.appearAnimate = true
            }
        }
    }
    
    private func switchPage(to index: Int) {
        guard index >= 0, index < totalPages else { return }
        
        // 1. 关闭前一页的动效状态，确保新一页有完整的级联淡入效果。
        appearAnimate = false
        
        // 2. 切换页面索引。
        currentPage = index
        
        // 3. 使用 Spring 弹性阻尼动画激活新卡片内的动效。
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            appearAnimate = true
        }
    }
    
    private func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分钟" : "\(minutes)分钟"
    }
}

private func formatDetailedDuration(_ seconds: TimeInterval) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    return hours > 0 ? "\(hours)小时\(minutes)分钟" : "\(minutes)分钟"
}

// MARK: - Slide Pages Definitions

// Cover Page
private struct CoverCard: View {
    let year: Int
    let appear: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 46))
                .foregroundStyle(
                    LinearGradient(colors: [AnnualReportView.studyColor, AnnualReportView.entertainmentColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .scaleEffect(appear ? 1.0 : 0.7)
                .opacity(appear ? 1.0 : 0.0)
            
            VStack(spacing: 8) {
                Text(String(year))
                    .font(.system(size: 54, weight: .black, design: .monospaced))
                    .foregroundColor(AnnualReportView.primaryText)
                    .tracking(4)
                
                Text("时间的回响")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AnnualReportView.primaryText)
                
                Text("— GrandleTick 年度学习报告 —")
                    .font(.system(size: 12))
                    .foregroundColor(AnnualReportView.secondaryText)
            }
            .offset(y: appear ? 0 : 20)
            .opacity(appear ? 1.0 : 0.0)
            
            Spacer()
            
            Text("轻触右下角箭头，开启您的专注旅程")
                .font(.system(size: 11))
                .foregroundColor(AnnualReportView.tertiaryText)
                .padding(.bottom, 40)
                .opacity(appear ? 1.0 : 0.0)
        }
        .padding(32)
    }
}

// Page 1: Overview
private struct AnnualOverviewCard: View {
    let studyDuration: TimeInterval
    let activeDays: Int
    let averageDailyDuration: TimeInterval
    let topAppSummary: AppDurationSummary?
    let comparison: ReportComparison?
    let appear: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleSection(title: "年度总览", subtitle: "把这一年的核心专注指标先铺开")
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricTile(title: "学习总时长", value: formatDetailedDuration(studyDuration), icon: "clock.fill", tint: AnnualReportView.studyColor)
                metricTile(title: "活跃天数", value: "\(activeDays) 天", icon: "calendar.badge.checkmark", tint: .green)
                metricTile(title: "日均学习", value: formatDetailedDuration(averageDailyDuration), icon: "chart.bar.fill", tint: .orange)
                metricTile(title: "首位应用", value: topAppSummary?.displayName ?? "暂无数据", icon: "app.badge.fill", tint: .purple)
            }
            .opacity(appear ? 1.0 : 0.0)
            .offset(y: appear ? 0 : 16)
            
            if let comparison {
                comparisonPanel(comparison)
                    .opacity(appear ? 1.0 : 0.0)
                    .offset(y: appear ? 0 : 16)
            }
            
            Spacer()
        }
        .padding(40)
    }
    
    private func metricTile(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
            
            Text(title)
                .font(.caption)
                .foregroundColor(AnnualReportView.secondaryText)
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AnnualReportView.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(14)
        .background(AnnualReportView.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AnnualReportView.borderColor, lineWidth: 1)
        )
    }
    
    private func comparisonPanel(_ comparison: ReportComparison) -> some View {
        let isGrowing = comparison.totalDurationDelta >= 0
        let rateText = comparison.totalDurationChangeRate.map { String(format: "%.0f%%", abs($0) * 100) } ?? "无法比较"
        
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((isGrowing ? Color.green : Color.orange).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: isGrowing ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isGrowing ? .green : .orange)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text("相比去年")
                    .font(.caption)
                    .foregroundColor(AnnualReportView.secondaryText)
                Text("\(isGrowing ? "增加" : "减少") \(formatDetailedDuration(abs(comparison.totalDurationDelta)))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AnnualReportView.primaryText)
                Text("活跃天数变化 \(comparison.activeDaysDelta >= 0 ? "+" : "")\(comparison.activeDaysDelta) 天 · 变化率 \(rateText)")
                    .font(.system(size: 11))
                    .foregroundColor(AnnualReportView.tertiaryText)
            }
            Spacer()
        }
        .padding(16)
        .background(AnnualReportView.softFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AnnualReportView.borderColor, lineWidth: 1)
        )
    }
}

// Page 1: Ratio
private struct FocusRatioCard: View {
    let studyDuration: TimeInterval
    let entertainmentDuration: TimeInterval
    let appear: Bool
    
    private var total: TimeInterval {
        max(1, studyDuration + entertainmentDuration)
    }
    
    private var studyRatio: Double {
        studyDuration / total
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            titleSection(title: "专注与休闲的张力", subtitle: "时间在不同场景下的分布比例")
            
            VStack(spacing: 24) {
                // 学习时长大字
                VStack(alignment: .leading, spacing: 6) {
                    Text("专注学习时长")
                        .font(.caption)
                        .foregroundColor(AnnualReportView.studyColor)
                    Text(formatDetailedDuration(studyDuration))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AnnualReportView.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
                
                // 娱乐时长大字
                VStack(alignment: .leading, spacing: 6) {
                    Text("娱乐休闲时长")
                        .font(.caption)
                        .foregroundColor(AnnualReportView.entertainmentColor)
                    Text(formatDetailedDuration(entertainmentDuration))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AnnualReportView.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
                
                // 动态分配比例条
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            AnnualReportView.studyColor
                                .frame(width: geo.size.width * (appear ? studyRatio : 0))
                            AnnualReportView.entertainmentColor
                                .frame(width: geo.size.width * (1.0 - (appear ? studyRatio : 0)))
                        }
                        .cornerRadius(6)
                    }
                    .frame(height: 12)
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: appear)
                    
                    HStack {
                        Text(String(format: "学习占比 %.0f%%", studyRatio * 100))
                            .font(.caption)
                            .foregroundColor(AnnualReportView.studyColor)
                        Spacer()
                        Text(String(format: "娱乐占比 %.0f%%", (1.0 - studyRatio) * 100))
                            .font(.caption)
                            .foregroundColor(AnnualReportView.entertainmentColor)
                    }
                    .opacity(appear ? 1.0 : 0.0)
                }
            }
            Spacer()
        }
        .padding(40)
    }
    
    private func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分钟" : "\(minutes)分钟"
    }
}

// Page 2: Rhythm
private struct RhythmCard: View {
    let primarySlot: ReportTimeSlot?
    let earliest: Date?
    let latest: Date?
    let hourlyDurations: [Double]
    let appear: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            titleSection(title: "探寻高效的旋律", subtitle: "捕捉你日常专注的黄金时段与节奏")
            
            VStack(spacing: 20) {
                // 黄金时段
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.orange.opacity(0.15)).frame(width: 48, height: 48)
                        Image(systemName: "sun.max.fill").font(.system(size: 20)).foregroundColor(.orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("黄金专注时段")
                            .font(.caption).foregroundColor(AnnualReportView.secondaryText)
                        Text(primarySlot?.title ?? "全天平衡")
                            .font(.system(size: 20, weight: .bold)).foregroundColor(AnnualReportView.primaryText)
                    }
                    Spacer()
                }
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
                
                // 最早专注
                if let earliest {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Color.green.opacity(0.15)).frame(width: 48, height: 48)
                            Image(systemName: "sunrise.fill").font(.system(size: 20)).foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最早的破晓专注")
                                .font(.caption).foregroundColor(AnnualReportView.secondaryText)
                            Text(formatClock(earliest))
                                .font(.system(size: 20, weight: .bold)).foregroundColor(AnnualReportView.primaryText)
                            Text("晨曦微露时，你已踏上专注的旅途")
                                .font(.system(size: 10)).foregroundColor(AnnualReportView.tertiaryText)
                        }
                        Spacer()
                    }
                    .opacity(appear ? 1.0 : 0.0)
                    .offset(y: appear ? 0 : 15)
                }
                
                // 最晚专注
                if let latest {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Color(red: 0.65, green: 0.55, blue: 1.0).opacity(0.15)).frame(width: 48, height: 48)
                            Image(systemName: "moon.stars.fill").font(.system(size: 20)).foregroundColor(Color(red: 0.7, green: 0.6, blue: 1.0))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最晚的守夜专注")
                               .font(.caption).foregroundColor(AnnualReportView.secondaryText)
                            Text(formatClock(latest))
                                .font(.system(size: 20, weight: .bold)).foregroundColor(AnnualReportView.primaryText)
                            Text("夜阑人静，微弱窗口光芒伴你前行")
                                .font(.system(size: 10)).foregroundColor(AnnualReportView.tertiaryText)
                        }
                        Spacer()
                    }
                    .opacity(appear ? 1.0 : 0.0)
                    .offset(y: appear ? 0 : 15)
                }
            }
            
            hourlyHeatmap
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
            
            Spacer()
        }
        .padding(40)
    }
    
    private var hourlyHeatmap: some View {
        let maxValue = max(hourlyDurations.max() ?? 0, 1)
        
        return VStack(alignment: .leading, spacing: 10) {
            Text("24 小时专注热力")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AnnualReportView.primaryText)
            
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AnnualReportView.studyColor.opacity(0.22 + 0.68 * hourlyDurations[hour] / maxValue))
                        .frame(height: max(8, 54 * hourlyDurations[hour] / maxValue))
                        .frame(maxWidth: .infinity)
                        .help("\(hour):00 · \(formatCompactDuration(hourlyDurations[hour]))")
                }
            }
            .frame(height: 60, alignment: .bottom)
            
            HStack {
                Text("0")
                Spacer()
                Text("6")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("24")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(AnnualReportView.tertiaryText)
        }
        .padding(14)
        .background(AnnualReportView.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AnnualReportView.borderColor, lineWidth: 1)
        )
    }
    
    private func formatClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分"
    }
}

// Page 4: Content Mix
private struct ContentMixCard: View {
    let websiteDuration: TimeInterval
    let pdfDuration: TimeInterval
    let topApps: [RankingEntry]
    let totalDuration: TimeInterval
    let appear: Bool
    
    private var contentTotal: TimeInterval {
        max(1, websiteDuration + pdfDuration)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            titleSection(title: "内容结构", subtitle: "从载体和应用两个角度观察年度活动来源")
            
            VStack(spacing: 14) {
                mixBar(
                    title: "网页资料",
                    value: websiteDuration,
                    total: contentTotal,
                    color: AnnualReportView.websiteColor,
                    icon: "globe"
                )
                mixBar(
                    title: "PDF 阅读",
                    value: pdfDuration,
                    total: contentTotal,
                    color: AnnualReportView.pdfColor,
                    icon: "doc.richtext.fill"
                )
            }
            .opacity(appear ? 1.0 : 0.0)
            .offset(y: appear ? 0 : 15)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("年度应用 Top 3")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AnnualReportView.primaryText)
                
                if topApps.isEmpty {
                    noDataRow(text: "今年还没有可展示的应用排行")
                } else {
                    ForEach(Array(topApps.prefix(3).enumerated()), id: \.element.id) { index, item in
                        appRankRow(index: index + 1, item: item)
                    }
                }
            }
            .padding(16)
            .background(AnnualReportView.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AnnualReportView.borderColor, lineWidth: 1)
            )
            .opacity(appear ? 1.0 : 0.0)
            .offset(y: appear ? 0 : 15)
            
            Spacer()
        }
        .padding(40)
    }
    
    private func mixBar(title: String, value: TimeInterval, total: TimeInterval, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AnnualReportView.primaryText)
                Spacer()
                Text(formatCompactDuration(value))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(AnnualReportView.secondaryText)
            }
            
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.14))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color)
                            .frame(width: geo.size.width * min(1, value / total))
                    }
            }
            .frame(height: 10)
            
            Text(String(format: "占内容载体 %.0f%%", value / total * 100))
                .font(.system(size: 10))
                .foregroundColor(AnnualReportView.tertiaryText)
        }
        .padding(14)
        .background(AnnualReportView.softFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private func appRankRow(index: Int, item: RankingEntry) -> some View {
        let share = totalDuration > 0 ? item.totalTime / totalDuration : 0
        
        return HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AnnualReportView.studyColor.opacity(index == 1 ? 1.0 : 0.68)))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AnnualReportView.primaryText)
                    .lineLimit(1)
                Text(String(format: "占年度总时长 %.0f%%", share * 100))
                    .font(.system(size: 10))
                    .foregroundColor(AnnualReportView.tertiaryText)
            }
            
            Spacer()
            
            Text(formatCompactDuration(item.totalTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(AnnualReportView.secondaryText)
        }
        .padding(.vertical, 6)
    }
    
    private func noDataRow(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(AnnualReportView.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }
    
    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分"
    }
}

// Page 3: Companions
private struct CompanionCard: View {
    let topWebsites: [RankingEntry]
    let topPDFs: [RankingEntry]
    let appear: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            titleSection(title: "与你同行的载体", subtitle: "这一年陪伴你最多的书页与网页")
            
            VStack(alignment: .leading, spacing: 20) {
                // 最爱阅读的书册 (PDF)
                VStack(alignment: .leading, spacing: 10) {
                    Label("年度书册 (PDF)", systemImage: "doc.richtext.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AnnualReportView.studyColor)
                    
                    if let topPDF = topPDFs.first {
                        companionRow(name: topPDF.name, duration: topPDF.totalTime)
                    } else {
                        noDataRow(text: "今年还没有阅读 PDF 记录")
                    }
                }
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
                
                // 最爱驻足的网站 (Web)
                VStack(alignment: .leading, spacing: 10) {
                    Label("年度学习网站", systemImage: "globe")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AnnualReportView.entertainmentColor)
                    
                    if let topWeb = topWebsites.first {
                        companionRow(name: topWeb.name, duration: topWeb.totalTime)
                    } else {
                        noDataRow(text: "今年还没有白名单域名学习记录")
                    }
                }
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
            }
            
            Spacer()
        }
        .padding(40)
    }
    
    private func companionRow(name: String, duration: TimeInterval) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AnnualReportView.primaryText)
                .lineLimit(1)
            Spacer()
            Text(formatCompactDuration(duration))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(AnnualReportView.secondaryText)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(AnnualReportView.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AnnualReportView.borderColor, lineWidth: 1)
        )
    }
    
    private func noDataRow(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(AnnualReportView.tertiaryText)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AnnualReportView.softFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分"
    }
}

// Page 4: Streak
private struct StreakCard: View {
    let longestStreak: Int
    let strongestDay: DaySummary?
    let shortestActiveDay: DaySummary?
    let activeDays: Int
    let appear: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            titleSection(title: "刻入时光的坚守", subtitle: "每一次启动都凝聚着恒心与自律")
            
            VStack(spacing: 24) {
                // 最长坚持
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.red.opacity(0.12)).frame(width: 48, height: 48)
                        Image(systemName: "flame.fill").font(.system(size: 20)).foregroundColor(.red)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最长连续坚持")
                            .font(.caption).foregroundColor(AnnualReportView.secondaryText)
                        Text("\(longestStreak) 天")
                            .font(.system(size: 24, weight: .bold)).foregroundColor(AnnualReportView.primaryText)
                    }
                    Spacer()
                }
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
                
                // 累计活跃天数
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.12)).frame(width: 48, height: 48)
                        Image(systemName: "calendar.badge.checkmark").font(.system(size: 20)).foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("累计活跃天数")
                            .font(.caption).foregroundColor(AnnualReportView.secondaryText)
                        Text("\(activeDays) 天")
                            .font(.system(size: 24, weight: .bold)).foregroundColor(AnnualReportView.primaryText)
                    }
                    Spacer()
                }
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
                
                // 单日最高专注
                if let strongestDay {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.12)).frame(width: 48, height: 48)
                            Image(systemName: "trophy.fill").font(.system(size: 20)).foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("单日最强爆发")
                                .font(.caption).foregroundColor(AnnualReportView.secondaryText)
                            Text(formatCompactDuration(strongestDay.totalTime))
                                .font(.system(size: 24, weight: .bold)).foregroundColor(AnnualReportView.primaryText)
                            Text("在 \(formatDate(strongestDay.date))，你与高强度的心流融为一体")
                                .font(.system(size: 10)).foregroundColor(AnnualReportView.tertiaryText)
                        }
                        Spacer()
                    }
                    .opacity(appear ? 1.0 : 0.0)
                    .offset(y: appear ? 0 : 15)
                }
                
                if let shortestActiveDay, shortestActiveDay.totalTime > 0 {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Color.indigo.opacity(0.12)).frame(width: 48, height: 48)
                            Image(systemName: "gauge.low").font(.system(size: 20)).foregroundColor(.indigo)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最低学习日")
                                .font(.caption).foregroundColor(AnnualReportView.secondaryText)
                            Text(formatCompactDuration(shortestActiveDay.totalTime))
                                .font(.system(size: 20, weight: .bold)).foregroundColor(AnnualReportView.primaryText)
                            Text("\(formatDate(shortestActiveDay.date)) 留下了可继续补强的空间")
                                .font(.system(size: 10)).foregroundColor(AnnualReportView.tertiaryText)
                        }
                        Spacer()
                    }
                    .opacity(appear ? 1.0 : 0.0)
                    .offset(y: appear ? 0 : 15)
                }
            }
            
            Spacer()
        }
        .padding(40)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
    
    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分"
    }
}

// Page 5: Archetype
private struct ArchetypeCard: View {
    let pdfDuration: TimeInterval
    let websiteDuration: TimeInterval
    let longestStreak: Int
    let primarySlot: ReportTimeSlot?
    let actionReset: () -> Void
    let appear: Bool
    
    private var archetypeTitle: String {
        if pdfDuration > websiteDuration {
            return "学海探索家"
        } else if longestStreak >= 7 {
            return "深度修行者"
        } else if primarySlot == .lateNight {
            return "极光守夜人"
        } else {
            return "平衡雕刻师"
        }
    }
    
    private var archetypeDesc: String {
        if pdfDuration > websiteDuration {
            return "您偏爱静心啃读 PDF 书册与笔记，通过阅读汲取体系化的知识。默默沉淀是您的专属姿态。"
        } else if longestStreak >= 7 {
            return "您的自律如同潮汐规律前行。一旦立下目标，连续的坚守就是您的力量底色。"
        } else if primarySlot == .lateNight {
            return "万籁俱寂时您的灵感火花最是灿烂。您习惯在寂静星空里点燃专注之火。"
        } else {
            return "游刃于网页资料与本地方案之间，在不同的学习任务中保持高效与平衡。"
        }
    }
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // 徽章动画
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [AnnualReportView.studyColor.opacity(0.12), AnnualReportView.pdfColor.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle().stroke(AnnualReportView.borderColor, lineWidth: 1)
                    )
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .scaleEffect(appear ? 1.0 : 0.7)
            .opacity(appear ? 1.0 : 0.0)
            
            // 人格标题
            VStack(spacing: 8) {
                Text("您的年度时间人格")
                    .font(.caption)
                    .foregroundColor(AnnualReportView.secondaryText)
                
                Text(archetypeTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AnnualReportView.primaryText)
                    .tracking(2)
            }
            .opacity(appear ? 1.0 : 0.0)
            
            // 人格说明
            Text(archetypeDesc)
                .font(.system(size: 13))
                .foregroundColor(AnnualReportView.secondaryText)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
            
            Spacer()
            
            // 重读按钮
            Button(action: actionReset) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("重读报告")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AnnualReportView.studyColor)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Capsule().stroke(AnnualReportView.studyColor.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .opacity(appear ? 1.0 : 0.0)
            .padding(.bottom, 24)
        }
        .padding(32)
    }
}

// Title Section Component helper
@ViewBuilder
private func titleSection(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(AnnualReportView.primaryText)
        Text(subtitle)
            .font(.caption)
            .foregroundColor(AnnualReportView.secondaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - Supporting Views

// Frosted Glass Effect View
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Light Report Background View
struct LightReportBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.98, blue: 0.95),
                    Color(red: 0.94, green: 0.97, blue: 1.00),
                    Color(red: 0.98, green: 0.96, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 1. 用低透明度斜向纹理增强纸面层次，避免浅色报告显得单薄，同时不抢占统计内容的视觉权重。
            VStack(spacing: 18) {
                ForEach(0..<18, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: 1)
                }
            }
            .rotationEffect(.degrees(-18))
            .scaleEffect(1.35)
            
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.58), Color.white.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

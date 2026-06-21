import SwiftUI
import SwiftData
import Charts

// MARK: - Annual Report View

struct AnnualReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var engine = StatisticsEngine()
    @State private var currentPage = 0
    @State private var isLoading = true
    @State private var appearAnimate = false
    
    private let totalPages = 6
    private let calendar = Calendar.current
    
    var body: some View {
        ZStack {
            // 1. 极光动感炫彩背景。
            AuroraBackground()
            
            // 2. 主卡片视图与导航控制。
            VStack(spacing: 20) {
                if isLoading {
                    loadingView
                } else {
                    mainCardDeck
                }
            }
            .frame(width: 480, height: 640)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 15)
            
            // 3. 右上角浮动关闭按钮。
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
                Spacer()
            }
            .frame(width: 480, height: 640)
        }
        .frame(width: 480, height: 640)
        .onAppear {
            loadYearlyData()
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
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private var mainCardDeck: some View {
        VStack(spacing: 0) {
            // 1. 内容切换卡片区，带过渡动画。
            ZStack {
                Group {
                    switch currentPage {
                    case 0:
                        CoverCard(appear: appearAnimate)
                    case 1:
                        FocusRatioCard(
                            studyDuration: engine.studyDuration,
                            entertainmentDuration: engine.entertainmentDuration,
                            appear: appearAnimate
                        )
                    case 2:
                        RhythmCard(
                            primarySlot: engine.primaryTimeSlot,
                            earliest: engine.earliestStudyStart,
                            latest: engine.latestStudyEnd,
                            appear: appearAnimate
                        )
                    case 3:
                        CompanionCard(
                            topWebsites: engine.topWebsites,
                            topPDFs: engine.topPDFs,
                            appear: appearAnimate
                        )
                    case 4:
                        StreakCard(
                            longestStreak: engine.longestStreak,
                            strongestDay: engine.strongestDay,
                            activeDays: engine.activeDays,
                            appear: appearAnimate
                        )
                    case 5:
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
                        .foregroundColor(currentPage > 0 ? .white : .white.opacity(0.15))
                        .padding(10)
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 0)
                
                Spacer()
                
                // 3. 点状页面指示器。
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.blue : Color.white.opacity(0.25))
                            .frame(width: index == currentPage ? 8 : 6, height: index == currentPage ? 8 : 6)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                
                Spacer()
                
                Button(action: { switchPage(to: currentPage + 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(currentPage < totalPages - 1 ? .white : .white.opacity(0.15))
                        .padding(10)
                }
                .buttonStyle(.plain)
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

// MARK: - Slide Pages Definitions

// Cover Page
private struct CoverCard: View {
    let appear: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 46))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .scaleEffect(appear ? 1.0 : 0.7)
                .opacity(appear ? 1.0 : 0.0)
            
            VStack(spacing: 8) {
                Text("2026")
                    .font(.system(size: 54, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(4)
                
                Text("时间的回响")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("— GrandleTick 年度学习报告 —")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .offset(y: appear ? 0 : 20)
            .opacity(appear ? 1.0 : 0.0)
            
            Spacer()
            
            Text("轻触右下角箭头，开启您的专注旅程")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
                .padding(.bottom, 40)
                .opacity(appear ? 1.0 : 0.0)
        }
        .padding(32)
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
                        .foregroundColor(.blue.opacity(0.8))
                    Text(formatDetailedDuration(studyDuration))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
                
                // 娱乐时长大字
                VStack(alignment: .leading, spacing: 6) {
                    Text("娱乐休闲时长")
                        .font(.caption)
                        .foregroundColor(.purple.opacity(0.8))
                    Text(formatDetailedDuration(entertainmentDuration))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 15)
                
                // 动态分配比例条
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Color.blue
                                .frame(width: geo.size.width * (appear ? studyRatio : 0))
                            Color.purple
                                .frame(width: geo.size.width * (1.0 - (appear ? studyRatio : 0)))
                        }
                        .cornerRadius(6)
                    }
                    .frame(height: 12)
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: appear)
                    
                    HStack {
                        Text(String(format: "学习占比 %.0f%%", studyRatio * 100))
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                        Text(String(format: "娱乐占比 %.0f%%", (1.0 - studyRatio) * 100))
                            .font(.caption)
                            .foregroundColor(.purple)
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
    let appear: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
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
                            .font(.caption).foregroundColor(.white.opacity(0.5))
                        Text(primarySlot?.title ?? "全天平衡")
                            .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
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
                                .font(.caption).foregroundColor(.white.opacity(0.5))
                            Text(formatClock(earliest))
                                .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                            Text("晨曦微露时，你已踏上专注的旅途")
                                .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
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
                            Circle().fill(Color.indigo.opacity(0.15)).frame(width: 48, height: 48)
                            Image(systemName: "moon.stars.fill").font(.system(size: 20)).foregroundColor(.indigo)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最晚的守夜专注")
                                .font(.caption).foregroundColor(.white.opacity(0.5))
                            Text(formatClock(latest))
                                .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                            Text("夜阑人静，微弱窗口光芒伴你前行")
                                .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
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
    
    private func formatClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
                        .foregroundColor(.blue.opacity(0.9))
                    
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
                        .foregroundColor(.purple.opacity(0.9))
                    
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
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            Text(formatCompactDuration(duration))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
    
    private func noDataRow(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.white.opacity(0.3))
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
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
                            .font(.caption).foregroundColor(.white.opacity(0.5))
                        Text("\(longestStreak) 天")
                            .font(.system(size: 24, weight: .bold)).foregroundColor(.white)
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
                            .font(.caption).foregroundColor(.white.opacity(0.5))
                        Text("\(activeDays) 天")
                            .font(.system(size: 24, weight: .bold)).foregroundColor(.white)
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
                                .font(.caption).foregroundColor(.white.opacity(0.5))
                            Text(formatCompactDuration(strongestDay.totalTime))
                                .font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                            Text("在 \(formatDate(strongestDay.date))，你与高强度的心流融为一体")
                                .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
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
                        LinearGradient(colors: [.blue.opacity(0.12), .purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
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
                    .foregroundColor(.white.opacity(0.5))
                
                Text(archetypeTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(2)
            }
            .opacity(appear ? 1.0 : 0.0)
            
            // 人格说明
            Text(archetypeDesc)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
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
                .foregroundColor(.white.opacity(0.6))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
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
            .foregroundColor(.white)
        Text(subtitle)
            .font(.caption)
            .foregroundColor(.white.opacity(0.5))
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

// Aurora Background Animation View
struct AuroraBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.09)
                .ignoresSafeArea()
            
            Circle()
                .fill(Color.blue.opacity(0.25))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: animate ? 120 : -120, y: animate ? -140 : 140)
            
            Circle()
                .fill(Color.purple.opacity(0.25))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: animate ? -140 : 140, y: animate ? 120 : -120)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

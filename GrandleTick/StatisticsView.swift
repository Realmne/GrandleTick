import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivityLog.startTime, order: .reverse) private var allLogs: [ActivityLog]
    
    @State private var whitelist = WhitelistManager.shared
    @State private var cachedFilteredLogs: [ActivityLog] = []
    @State private var cachedAppSummary: [(name: String, totalTime: TimeInterval)] = []
    
    // ⭐ 移除了 hoveredAppName，让它只归属图表子视图自己管理
    
    var body: some View {
        VStack(spacing: 0) {
            // --- 1. 固定在顶部的独立标题栏 ---
            HStack(alignment: .bottom) {
                Text("今日活动总结")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text("GrandleTick 历史记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 25)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .background(Material.regular)
            .overlay(Divider(), alignment: .bottom)
            
            // --- 2. 数据滚动区域 ---
            if cachedAppSummary.isEmpty {
                VStack(spacing: 15) {
                    Spacer()
                    Image(systemName: "tray.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("当前白名单暂无匹配的活动记录")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        
                        // ⭐ 性能优化：将图表完全独立成子视图，实现“状态隔离”
                        AppSummaryChartView(summaryData: cachedAppSummary)
                            .padding(.horizontal, 5)
                        
                        // 列表详情 (此时图表怎么刷新，都不会再拖累这个庞大的列表了)
                        VStack(spacing: 12) {
                            ForEach(cachedAppSummary, id: \.name) { app in
                                HStack(alignment: .top, spacing: 15) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)).frame(width: 36, height: 36)
                                        Text(String(app.name.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)).foregroundColor(.accentColor)
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(app.name).font(.system(size: 15, weight: .semibold))
                                            Spacer()
                                            Text(formatDuration(app.totalTime)).font(.system(size: 14, design: .monospaced)).foregroundColor(.secondary)
                                        }
                                        
                                        let subItems = details(for: app.name)
                                        ForEach(subItems, id: \.title) { sub in
                                            HStack(alignment: .top) {
                                                Text("•").foregroundColor(.secondary)
                                                Text(sub.title).font(.system(size: 12)).foregroundColor(.primary.opacity(0.7)).lineLimit(2)
                                                Spacer()
                                                if subItems.count > 1 { Text(formatDuration(sub.duration)).font(.system(size: 11)).foregroundColor(.secondary.opacity(0.8)) }
                                            }
                                            .contextMenu {
                                                Button(role: .destructive) { deleteSpecificItem(appName: app.name, windowTitle: sub.title) } label: {
                                                    Label("删除此条记录", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                }.padding(15).background(Color.primary.opacity(0.04)).cornerRadius(15)
                            }
                        }
                    }
                    .padding(25)
                }
            }
        }
        .frame(width: 500, height: 650)
        .ignoresSafeArea(.all, edges: .top)
        .onAppear { calculateData() }
        .onChange(of: allLogs) { _, _ in calculateData() }
        .onChange(of: whitelist.whitelistedApps) { _, _ in calculateData() }
        .onChange(of: whitelist.whitelistedDomains) { _, _ in calculateData() }
    }
    
    private func deleteSpecificItem(appName: String, windowTitle: String) {
        let logsToDelete = allLogs.filter { $0.appName == appName && $0.windowTitle == windowTitle }
        for log in logsToDelete { modelContext.delete(log) }
        try? modelContext.save()
    }
    
    private func calculateData() {
        cachedFilteredLogs = allLogs.filter { log in
            if log.windowTitle.contains("权限") || log.windowTitle.contains("未知") || log.appName.isEmpty { return false }
            
            let logAppName = log.appName.lowercased()
            let isBrowser = logAppName.contains("safari") || logAppName.contains("chrome") || logAppName.contains("edge")
            
            let isAppWhitelisted = whitelist.whitelistedApps.contains { app in
                let target = app.lowercased()
                return target == logAppName || target.contains(logAppName) || logAppName.contains(target)
            }
            if !isAppWhitelisted { return false }
            
            if isBrowser {
                let logTitle = log.windowTitle.lowercased()
                if logTitle.contains("网页加载中") { return true }
                return whitelist.whitelistedDomains.contains { domain in
                    let keyword = domain.components(separatedBy: ".").first?.lowercased() ?? domain.lowercased()
                    return logTitle.contains(keyword) || (keyword == "bilibili" && logTitle.contains("哔哩哔哩"))
                }
            }
            return true
        }
        
        let grouped = Dictionary(grouping: cachedFilteredLogs, by: { $0.appName })
        cachedAppSummary = grouped.map { (name: $0.key, totalTime: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.totalTime > $1.totalTime }
    }
    
    func details(for appName: String) -> [(title: String, duration: TimeInterval)] {
        let appLogs = cachedFilteredLogs.filter { $0.appName == appName }
        let grouped = Dictionary(grouping: appLogs, by: { $0.windowTitle })
        return grouped.map { (title: $0.key, duration: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.duration > $1.duration }
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - 独立的图表组件 (状态隔离核心)
struct AppSummaryChartView: View {
    let summaryData: [(name: String, totalTime: TimeInterval)]
    
    // ⭐ 这个状态现在只属于图表自己，改变它不会再触发外层巨大列表的重绘
    @State private var hoveredAppName: String?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Chart(summaryData, id: \.name) { item in
                BarMark(
                    x: .value("时长", item.totalTime / 60),
                    y: .value("应用", item.name)
                )
                .foregroundStyle(by: .value("应用", item.name))
                .cornerRadius(4)
                .opacity(hoveredAppName == nil || hoveredAppName == item.name ? 1.0 : 0.5)
            }
            .frame(height: 180)
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                TooltipOverlay(proxy: proxy, summaryData: summaryData, hoveredAppName: $hoveredAppName)
            }
        }
    }
}

// 悬浮交互层
struct TooltipOverlay: View {
    let proxy: ChartProxy
    let summaryData: [(name: String, totalTime: TimeInterval)]
    @Binding var hoveredAppName: String?
    @State private var mousePosition: CGPoint?
    
    var body: some View {
        GeometryReader { geometry in
            Color.clear.contentShape(Rectangle())
                .onContinuousHover { phase in
                    // 强制关闭系统在状态改变时的隐式布局动画，保证纯粹的性能
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    
                    withTransaction(transaction) {
                        switch phase {
                        case .active(let location):
                            mousePosition = location
                            let currentHover = proxy.value(atY: location.y, as: String.self)
                            // 仅当真的跨越了不同的柱子时，才去触发状态变更
                            if hoveredAppName != currentHover {
                                hoveredAppName = currentHover
                            }
                        case .ended:
                            mousePosition = nil
                            if hoveredAppName != nil {
                                hoveredAppName = nil
                            }
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let pos = mousePosition, let appName = hoveredAppName, let hoveredApp = summaryData.first(where: { $0.name == appName }) {
                        MouseTooltipView(duration: hoveredApp.totalTime)
                        // 去除了这里的 animation，让气泡绝对无延迟地 1:1 跟随鼠标
                            .offset(x: pos.x + 15, y: pos.y - 30)
                    }
                }
        }
    }
}

// 气泡外观
struct MouseTooltipView: View {
    let duration: TimeInterval
    var body: some View {
        Text(formatDetailedDuration(duration))
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.85)))
            .fixedSize()
    }
    
    func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }
}

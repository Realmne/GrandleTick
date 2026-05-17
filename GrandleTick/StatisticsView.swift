import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivityLog.startTime, order: .reverse) private var allLogs: [ActivityLog]
    
    @State private var whitelist = WhitelistManager.shared
    @State private var filteredLogs: [ActivityLog] = []
    @State private var summaryEntries: [(name: String, totalTime: TimeInterval)] = []
    
    var body: some View {
        VStack(spacing: 0) {
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
            
            statisticsContent
        }
        .frame(width: 500, height: 650)
        .ignoresSafeArea(.all, edges: .top)
        .onAppear { calculateData() }
        .onChange(of: allLogs) { _, _ in calculateData() }
        .onChange(of: whitelist.whitelistedApps) { _, _ in calculateData() }
        .onChange(of: whitelist.whitelistedDomains) { _, _ in calculateData() }
    }

    @ViewBuilder
    private var statisticsContent: some View {
        if summaryEntries.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    SummaryChartView(summaryData: summaryEntries)
                        .padding(.horizontal, 5)
                    
                    VStack(spacing: 12) {
                        ForEach(summaryEntries, id: \.name) { summaryEntry in
                            SummaryEntryCardView(
                                summaryEntry: summaryEntry,
                                detailEntries: details(for: summaryEntry.name),
                                formatDuration: formatDuration,
                                onDelete: { windowTitle in
                                    deleteSpecificItem(selectedSummaryName: summaryEntry.name, windowTitle: windowTitle)
                                }
                            )
                        }
                    }
                }
                .padding(25)
            }
        }
    }

    private var emptyStateView: some View {
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
    }

    private func deleteSpecificItem(selectedSummaryName: String, windowTitle: String) {
        let logsToDelete = filteredLogs.filter {
            summaryName(for: $0) == selectedSummaryName && $0.windowTitle == windowTitle
        }
        for log in logsToDelete { modelContext.delete(log) }
        try? modelContext.save()
    }
    
    private func calculateData() {
        // 1. 先过滤无效记录和未授权状态记录。
        //    这一步只保留真正参与统计的活动数据，避免图表和列表被异常状态污染。
        filteredLogs = allLogs.filter { log in
            if log.windowTitle.contains("权限") || log.windowTitle.contains("未知") || log.appName.isEmpty { return false }
            
            let lowercasedAppName = log.appName.lowercased()
            let isBrowserApp = lowercasedAppName.contains("safari") || lowercasedAppName.contains("chrome") || lowercasedAppName.contains("edge")
            
            // 2. 再检查应用白名单。
            //    浏览器和普通应用都必须先通过应用级白名单，才允许进入后续统计流程。
            let isWhitelistedApp = whitelist.whitelistedApps.contains { whitelistedApp in
                let lowercasedWhitelistedApp = whitelistedApp.lowercased()
                return lowercasedWhitelistedApp == lowercasedAppName
                    || lowercasedWhitelistedApp.contains(lowercasedAppName)
                    || lowercasedAppName.contains(lowercasedWhitelistedApp)
            }
            if !isWhitelistedApp { return false }
            
            if isBrowserApp {
                let lowercasedWindowTitle = log.windowTitle.lowercased()
                if lowercasedWindowTitle.contains("网页加载中") { return true }
                
                // 3. 浏览器记录优先按真实域名过滤。
                //    只要能从数据库字段或标题里识别出域名，这条记录就会保留下来。
                return browserDomain(for: log) != nil
            }
            return true
        }
        
        // 4. 最终汇总时，浏览器按真实域名分组，普通应用按应用名分组。
        //    这样 `chatgpt.com` 和 `huya.com` 不会再先合并到同一个浏览器应用下面。
        let grouped = Dictionary(grouping: filteredLogs, by: summaryName(for:))
        summaryEntries = grouped.map { (name: $0.key, totalTime: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.totalTime > $1.totalTime }
    }
    
    func details(for summaryName: String) -> [(title: String, duration: TimeInterval)] {
        let logs = filteredLogs.filter { self.summaryName(for: $0) == summaryName }
        let grouped = Dictionary(grouping: logs, by: { $0.windowTitle })
        return grouped.map { (title: $0.key, duration: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.duration > $1.duration }
    }

    private func isBrowserApp(_ appName: String) -> Bool {
        let lowercasedAppName = appName.lowercased()
        return lowercasedAppName.contains("safari") || lowercasedAppName.contains("chrome") || lowercasedAppName.contains("edge")
    }

    private func browserDomain(for log: ActivityLog) -> String? {
        if let domain = log.domain, whitelist.whitelistedDomains.contains(domain) {
            return domain
        }
        
        // 1. 新记录优先使用数据库里已经保存好的真实域名。
        // 2. 老记录如果没有域名字段，再退化成标题关键词匹配。
        let lowercasedWindowTitle = log.windowTitle.lowercased()
        return whitelist.whitelistedDomains.first { domain in
            let keyword = domain.components(separatedBy: ".").first?.lowercased() ?? domain.lowercased()
            return lowercasedWindowTitle.contains(keyword) || (keyword == "bilibili" && lowercasedWindowTitle.contains("哔哩哔哩"))
        }
    }

    private func summaryName(for log: ActivityLog) -> String {
        if isBrowserApp(log.appName), let domain = browserDomain(for: log) {
            return domain
        }
        return log.appName
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

struct SummaryChartView: View {
    let summaryData: [(name: String, totalTime: TimeInterval)]
    
    @State private var hoveredSummaryName: String?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Chart(summaryData, id: \.name) { item in
                BarMark(
                    x: .value("时长", item.totalTime / 60),
                    y: .value("应用", item.name)
                )
                .foregroundStyle(by: .value("应用", item.name))
                .cornerRadius(4)
                .opacity(hoveredSummaryName == nil || hoveredSummaryName == item.name ? 1.0 : 0.5)
            }
            .frame(height: 180)
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                TooltipOverlay(proxy: proxy, summaryData: summaryData, hoveredSummaryName: $hoveredSummaryName)
            }
        }
    }
}

struct SummaryEntryCardView: View {
    let summaryEntry: (name: String, totalTime: TimeInterval)
    let detailEntries: [(title: String, duration: TimeInterval)]
    let formatDuration: (TimeInterval) -> String
    let onDelete: (String) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(summaryEntry.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(summaryEntry.name)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(formatDuration(summaryEntry.totalTime))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                ForEach(detailEntries, id: \.title) { detailEntry in
                    HStack(alignment: .top) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(detailEntry.title)
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.7))
                            .lineLimit(2)
                        Spacer()
                        if detailEntries.count > 1 {
                            Text(formatDuration(detailEntry.duration))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(detailEntry.title)
                        } label: {
                            Label("删除此条记录", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(15)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(15)
    }
}

struct TooltipOverlay: View {
    let proxy: ChartProxy
    let summaryData: [(name: String, totalTime: TimeInterval)]
    @Binding var hoveredSummaryName: String?
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
                            let currentHoveredSummaryName = proxy.value(atY: location.y, as: String.self)
                            if hoveredSummaryName != currentHoveredSummaryName {
                                hoveredSummaryName = currentHoveredSummaryName
                            }
                        case .ended:
                            mousePosition = nil
                            if hoveredSummaryName != nil {
                                hoveredSummaryName = nil
                            }
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let pos = mousePosition, let summaryName = hoveredSummaryName, let hoveredSummaryEntry = summaryData.first(where: { $0.name == summaryName }) {
                        MouseTooltipView(duration: hoveredSummaryEntry.totalTime)
                            .offset(x: pos.x + 15, y: pos.y - 30)
                    }
                }
        }
    }
}

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

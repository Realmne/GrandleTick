import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    // ⭐ 引入数据库上下文，用于执行删除操作
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \ActivityLog.startTime, order: .reverse) private var allLogs: [ActivityLog]
    
    @State private var cachedFilteredLogs: [ActivityLog] = []
    @State private var cachedAppSummary: [(name: String, totalTime: TimeInterval)] = []
    @State private var hoveredAppName: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text("今日活动总结").font(.system(size: 24, weight: .bold)).padding(.top)

                ZStack(alignment: .topLeading) {
                    Chart(cachedAppSummary, id: \.name) { item in
                        BarMark(x: .value("时长", item.totalTime / 60), y: .value("应用", item.name))
                            .foregroundStyle(by: .value("应用", item.name))
                            .cornerRadius(4)
                            .opacity(hoveredAppName == nil || hoveredAppName == item.name ? 1.0 : 0.5)
                    }
                    .frame(height: 180)
                    .chartLegend(.hidden)
                    .padding(.horizontal, 5)
                    .chartOverlay { proxy in
                        TooltipOverlay(
                            proxy: proxy,
                            summaryData: cachedAppSummary,
                            hoveredAppName: $hoveredAppName
                        )
                    }
                }
                
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
                                    // ⭐ 新增：为每一行添加右键菜单
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteSpecificItem(appName: app.name, windowTitle: sub.title)
                                        } label: {
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
        .frame(width: 500, height: 650)
        .onAppear { calculateData() }
        .onChange(of: allLogs) { _, _ in calculateData() }
    }
    
    // ⭐ 新增：遍历并删除数据库中匹配的应用名和标题的所有日志
    private func deleteSpecificItem(appName: String, windowTitle: String) {
        let logsToDelete = allLogs.filter { $0.appName == appName && $0.windowTitle == windowTitle }
        
        for log in logsToDelete {
            modelContext.delete(log)
        }
        
        do {
            try modelContext.save()
            print("🗑️ 已精准删除记录: [\(appName)] - [\(windowTitle)]")
        } catch {
            print("❌ 删除失败: \(error.localizedDescription)")
        }
    }
    
    private func calculateData() {
        cachedFilteredLogs = allLogs.filter { log in
            let isInvalid = log.windowTitle.contains("权限") || log.windowTitle.contains("未知") || log.appName.contains("受阻") || log.appName.isEmpty
            return !isInvalid
        }
        
        let grouped = Dictionary(grouping: cachedFilteredLogs, by: { $0.appName })
        cachedAppSummary = grouped.map { (key, value) in
            (name: key, totalTime: value.reduce(0) { $0 + $1.duration })
        }.sorted {
            if $0.totalTime == $1.totalTime { return $0.name < $1.name }
            return $0.totalTime > $1.totalTime
        }
    }
    
    func details(for appName: String) -> [(title: String, duration: TimeInterval)] {
        let appLogs = cachedFilteredLogs.filter { $0.appName == appName }
        let grouped = Dictionary(grouping: appLogs, by: { $0.windowTitle })
        
        return grouped.map { (key, value) in
            let total = value.reduce(0) { $0 + $1.duration }
            return (title: key, duration: total)
        }.sorted { $0.duration > $1.duration }
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// 独立的极简悬停遮罩层（保证极致丝滑）
struct TooltipOverlay: View {
    let proxy: ChartProxy
    let summaryData: [(name: String, totalTime: TimeInterval)]
    @Binding var hoveredAppName: String?
    @State private var mousePosition: CGPoint?
    
    var body: some View {
        GeometryReader { geometry in
            Color.clear.contentShape(Rectangle())
                .onContinuousHover { phase in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    
                    withTransaction(transaction) {
                        switch phase {
                        case .active(let location):
                            mousePosition = location
                            let currentHover = proxy.value(atY: location.y, as: String.self)
                            if hoveredAppName != currentHover { hoveredAppName = currentHover }
                        case .ended:
                            mousePosition = nil
                            hoveredAppName = nil
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let pos = mousePosition, let appName = hoveredAppName, let hoveredApp = summaryData.first(where: { $0.name == appName }) {
                        MouseTooltipView(duration: hoveredApp.totalTime)
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.85))
                    .shadow(color: .black.opacity(0.2), radius: 3)
            )
            .fixedSize()
    }
    func formatDetailedDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }
}

import SwiftUI

/// 列表分类模式：白名单（计入学习专注）与黑名单（计入娱乐休闲）
private enum ListMode: String, CaseIterable, Identifiable {
    case whitelist = "白名单 (学习)"
    case blacklist = "黑名单 (娱乐)"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .whitelist: return "book.closed.fill"
        case .blacklist: return "gamecontroller.fill"
        }
    }

    var tint: Color {
        switch self {
        case .whitelist: return AppDesign.primaryBlue
        case .blacklist: return AppDesign.leisurePurple
        }
    }
}

struct WhitelistView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var whitelistManager = WhitelistManager.shared
    @State private var selectedMode: ListMode = .whitelist
    @State private var contentVisible = false

    // MARK: - 白名单计算属性

    private var defaultWhitelistApps: [String] {
        whitelistManager.whitelistedApps
            .filter { whitelistManager.systemDefaultApps.contains($0) }
            .sorted()
    }

    private var customWhitelistApps: [String] {
        whitelistManager.whitelistedApps
            .filter { !whitelistManager.systemDefaultApps.contains($0) }
            .sorted()
    }

    private var defaultWhitelistDomains: [String] {
        whitelistManager.whitelistedDomains
            .filter { whitelistManager.systemDefaultDomains.contains($0) }
            .sorted()
    }

    private var customWhitelistDomains: [String] {
        whitelistManager.whitelistedDomains
            .filter { !whitelistManager.systemDefaultDomains.contains($0) }
            .sorted()
    }

    // MARK: - 黑名单计算属性

    private var defaultBlacklistApps: [String] {
        whitelistManager.blacklistedApps
            .filter { whitelistManager.systemDefaultBlacklistApps.contains($0) }
            .sorted()
    }

    private var customBlacklistApps: [String] {
        whitelistManager.blacklistedApps
            .filter { !whitelistManager.systemDefaultBlacklistApps.contains($0) }
            .sorted()
    }

    private var defaultBlacklistDomains: [String] {
        whitelistManager.blacklistedDomains
            .filter { whitelistManager.systemDefaultBlacklistDomains.contains($0) }
            .sorted()
    }

    private var customBlacklistDomains: [String] {
        whitelistManager.blacklistedDomains
            .filter { !whitelistManager.systemDefaultBlacklistDomains.contains($0) }
            .sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            modePickerView

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedMode == .whitelist {
                        whitelistContent
                    } else {
                        blacklistContent
                    }
                }
                .padding(24)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: reduceMotion || contentVisible ? 0 : 8)
                .animation(reduceMotion ? nil : AppDesign.animationCurve, value: selectedMode)
            }
            .background(AppDesign.appBackground)
        }
        .frame(minWidth: 520, minHeight: 680)
        .ignoresSafeArea(.all, edges: .top)
        .onAppear {
            withAnimation(reduceMotion ? nil : AppDesign.springAnimation) {
                contentVisible = true
            }
        }
    }

    // MARK: - 顶栏与分段选择器

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("名单管理")
                .font(.system(size: 24, weight: .bold))

            Text("自定义学习专注与娱乐计时的统计范围")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var modePickerView: some View {
        HStack(spacing: 8) {
            ForEach(ListMode.allCases) { mode in
                Button {
                    withAnimation(reduceMotion ? nil : AppDesign.animationCurve) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(selectedMode == mode ? mode.tint : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: AppDesign.controlCornerRadius, style: .continuous)
                            .fill(selectedMode == mode ? mode.tint.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppDesign.controlCornerRadius, style: .continuous)
                            .stroke(selectedMode == mode ? mode.tint.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    // MARK: - 白名单视图内容

    @ViewBuilder
    private var whitelistContent: some View {
        HStack(spacing: 14) {
            WhitelistCountCard(
                title: "学习应用",
                value: "\(whitelistManager.whitelistedApps.count)",
                detail: "自定义 \(customWhitelistApps.count) 项",
                symbolName: "macwindow.on.rectangle",
                tint: AppDesign.primaryBlue
            )

            WhitelistCountCard(
                title: "学习域名",
                value: "\(whitelistManager.whitelistedDomains.count)",
                detail: "自定义 \(customWhitelistDomains.count) 项",
                symbolName: "network",
                tint: AppDesign.websiteTeal
            )
        }

        HStack(spacing: 12) {
            Button(action: { addAppFromFinder(for: .whitelist) }) {
                Label("添加学习应用", systemImage: "plus.app.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppCapsuleButtonStyle(role: .primary))

            Button(action: { addDomainManually(for: .whitelist) }) {
                Label("添加学习域名", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppCapsuleButtonStyle(role: .primary))
        }

        WhitelistCategoryCard(
            title: "应用白名单",
            subtitle: "命中即计入学习专注时长",
            symbolName: "app.connected.to.app.below.fill",
            tint: AppDesign.primaryBlue,
            totalCount: whitelistManager.whitelistedApps.count,
            defaultTitle: "默认应用",
            defaultItems: defaultWhitelistApps,
            customTitle: "自定义应用",
            customItems: customWhitelistApps,
            emptyText: "无自定义学习应用",
            onDelete: { whitelistManager.removeApp($0) }
        )

        WhitelistCategoryCard(
            title: "域名白名单",
            subtitle: "在浏览器中访问命中即计入学习时长",
            symbolName: "globe.europe.africa.fill",
            tint: AppDesign.websiteTeal,
            totalCount: whitelistManager.whitelistedDomains.count,
            defaultTitle: "默认域名",
            defaultItems: defaultWhitelistDomains,
            customTitle: "自定义域名",
            customItems: customWhitelistDomains,
            emptyText: "无自定义学习域名",
            onDelete: { whitelistManager.removeDomain($0) }
        )

        hintSection(text: "白名单中的应用与网站将计入专注学习时长。浏览器记录需同时命中应用和域名白名单。")
    }

    // MARK: - 黑名单视图内容

    @ViewBuilder
    private var blacklistContent: some View {
        HStack(spacing: 14) {
            WhitelistCountCard(
                title: "娱乐应用",
                value: "\(whitelistManager.blacklistedApps.count)",
                detail: "自定义 \(customBlacklistApps.count) 项",
                symbolName: "gamecontroller.fill",
                tint: AppDesign.leisurePurple
            )

            WhitelistCountCard(
                title: "娱乐域名",
                value: "\(whitelistManager.blacklistedDomains.count)",
                detail: "自定义 \(customBlacklistDomains.count) 项",
                symbolName: "network.badge.shield.half.filled",
                tint: AppDesign.leisurePurple
            )
        }

        HStack(spacing: 12) {
            Button(action: { addAppFromFinder(for: .blacklist) }) {
                Label("添加娱乐应用", systemImage: "plus.app.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppCapsuleButtonStyle(role: .primary))

            Button(action: { addDomainManually(for: .blacklist) }) {
                Label("添加娱乐域名", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppCapsuleButtonStyle(role: .primary))
        }

        WhitelistCategoryCard(
            title: "应用黑名单",
            subtitle: "命中即直接计入娱乐与休闲时长",
            symbolName: "xmark.app.fill",
            tint: AppDesign.leisurePurple,
            totalCount: whitelistManager.blacklistedApps.count,
            defaultTitle: "默认应用",
            defaultItems: defaultBlacklistApps,
            customTitle: "自定义应用",
            customItems: customBlacklistApps,
            emptyText: "暂无黑名单应用（可点击上方添加）",
            onDelete: { whitelistManager.removeBlacklistApp($0) }
        )

        WhitelistCategoryCard(
            title: "域名黑名单",
            subtitle: "在浏览器中访问命中即计入娱乐时长",
            symbolName: "globe.badge.chevron.backward",
            tint: AppDesign.leisurePurple,
            totalCount: whitelistManager.blacklistedDomains.count,
            defaultTitle: "默认域名",
            defaultItems: defaultBlacklistDomains,
            customTitle: "自定义域名",
            customItems: customBlacklistDomains,
            emptyText: "暂无黑名单域名（可点击上方添加）",
            onDelete: { whitelistManager.removeBlacklistDomain($0) }
        )

        hintSection(text: "黑名单中的应用与网站将始终计入娱乐与休闲时长，优先级高于其它匹配规则。")
    }

    private func hintSection(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(.system(size: 14, weight: .semibold))

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.largeCornerRadius, style: .continuous)
                .fill(AppDesign.elevatedPanelBackground)
        )
    }

    // MARK: - 添加交互

    private func addAppFromFinder(for mode: ListMode) {
        // 1. 创建并配置打开文件面板以允许选择应用程序。
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        // 2. 激活应用以保证面板显示在前台。
        NSApp.activate(ignoringOtherApps: true)

        // 3. 运行面板并在用户确认选择后提取应用名称，根据当前所选分类存入白名单或黑名单。
        if panel.runModal() == .OK, let selectedAppUrl = panel.url {
            let appName = (selectedAppUrl.lastPathComponent as NSString).deletingPathExtension
            if mode == .whitelist {
                whitelistManager.addApp(appName)
            } else {
                whitelistManager.addBlacklistApp(appName)
            }
        }
    }

    private func addDomainManually(for mode: ListMode) {
        // 1. 创建并配置输入框及弹窗属性。
        let alert = NSAlert()
        alert.messageText = mode == .whitelist ? "添加学习域名（白名单）" : "添加娱乐域名（黑名单）"
        alert.informativeText = "例如：github.com 或 store.steampowered.com"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        alert.accessoryView = inputField
        
        // 2. 将输入框作为附加视图载入弹窗并激活前台。
        NSApp.activate(ignoringOtherApps: true)
        
        // 3. 运行弹窗并在用户确认后将输入的域名存入对应名单。
        if alert.runModal() == .alertFirstButtonReturn {
            let value = inputField.stringValue
            if mode == .whitelist {
                whitelistManager.addDomain(value)
            } else {
                whitelistManager.addBlacklistDomain(value)
            }
        }
    }
}

private struct WhitelistCategoryCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let totalCount: Int
    let defaultTitle: String
    let defaultItems: [String]
    let customTitle: String
    let customItems: [String]
    let emptyText: String
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppDesign.mediumCornerRadius, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 46, height: 46)

                    Image(systemName: symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                WhitelistPill(
                    text: "\(totalCount) 项",
                    tint: tint
                )
            }

            if !defaultItems.isEmpty {
                WhitelistSectionBlock(
                    title: defaultTitle,
                    items: defaultItems,
                    badgeText: "默认",
                    badgeTint: tint.opacity(0.85),
                    onDelete: onDelete
                )
            }

            WhitelistSectionBlock(
                title: customTitle,
                items: customItems,
                badgeText: "自定义",
                badgeTint: tint.opacity(0.75),
                emptyText: emptyText,
                onDelete: onDelete
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.largeCornerRadius, style: .continuous)
                .fill(AppDesign.panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.largeCornerRadius, style: .continuous)
                        .stroke(tint.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct WhitelistSectionBlock: View {
    let title: String
    let items: [String]
    let badgeText: String
    let badgeTint: Color
    var emptyText: String? = nil
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            if items.isEmpty {
                Text(emptyText ?? "无内容")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(items, id: \.self) { item in
                        WhitelistEntryCard(
                            name: item,
                            badgeText: badgeText,
                            badgeTint: badgeTint,
                            onDelete: { onDelete(item) }
                        )
                    }
                }
            }
        }
    }
}

private struct WhitelistEntryCard: View {
    let name: String
    let badgeText: String
    let badgeTint: Color
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppDesign.controlCornerRadius, style: .continuous)
                    .fill(AppDesign.panelBackground)
                    .frame(width: 36, height: 36)

                Image(systemName: symbolName(for: name))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                WhitelistPill(text: badgeText, tint: badgeTint)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppDesign.destructiveRed)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(AppDesign.destructiveRed.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.mediumCornerRadius, style: .continuous)
                .fill(AppDesign.elevatedPanelBackground)
        )
    }

    private func symbolName(for entry: String) -> String {
        if entry.contains(".") {
            return "globe"
        }

        let lowercased = entry.lowercased()
        if lowercased.contains("safari") || lowercased.contains("chrome") || lowercased.contains("edge") {
            return "safari"
        }
        if lowercased.contains("预览") || lowercased.contains("preview") {
            return "doc.richtext"
        }
        return "app"
    }
}

private struct WhitelistCountCard: View {
    let title: String
    let value: String
    let detail: String
    let symbolName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.largeCornerRadius, style: .continuous)
                .fill(AppDesign.panelBackground)
        )
    }
}

private struct WhitelistPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }
}


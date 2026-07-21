import SwiftUI

struct WhitelistView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var whitelistManager = WhitelistManager.shared
    @State private var contentVisible = false

    private var defaultApps: [String] {
        whitelistManager.whitelistedApps
            .filter { whitelistManager.systemDefaultApps.contains($0) }
            .sorted()
    }

    private var customApps: [String] {
        whitelistManager.whitelistedApps
            .filter { !whitelistManager.systemDefaultApps.contains($0) }
            .sorted()
    }

    private var defaultDomains: [String] {
        whitelistManager.whitelistedDomains
            .filter { whitelistManager.systemDefaultDomains.contains($0) }
            .sorted()
    }

    private var customDomains: [String] {
        whitelistManager.whitelistedDomains
            .filter { !whitelistManager.systemDefaultDomains.contains($0) }
            .sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    overviewSection
                    actionsSection

                    WhitelistCategoryCard(
                        title: "应用",
                        subtitle: "统计这些应用",
                        symbolName: "app.connected.to.app.below.fill",
                        tint: AppDesign.primaryBlue,
                        totalCount: whitelistManager.whitelistedApps.count,
                        defaultTitle: "默认",
                        defaultItems: defaultApps,
                        customTitle: "自定义",
                        customItems: customApps,
                        emptyText: "无自定义项",
                        onDelete: { whitelistManager.removeApp($0) }
                    )

                    WhitelistCategoryCard(
                        title: "域名",
                        subtitle: "统计这些域名",
                        symbolName: "globe.europe.africa.fill",
                        tint: AppDesign.websiteTeal,
                        totalCount: whitelistManager.whitelistedDomains.count,
                        defaultTitle: "默认",
                        defaultItems: defaultDomains,
                        customTitle: "自定义",
                        customItems: customDomains,
                        emptyText: "无自定义项",
                        onDelete: { whitelistManager.removeDomain($0) }
                    )

                    hintSection
                }
                .padding(24)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: reduceMotion || contentVisible ? 0 : 8)
            }
            .background(AppDesign.appBackground)
        }
        .frame(minWidth: 520, minHeight: 660)
        .ignoresSafeArea(.all, edges: .top)
        .onAppear {
            withAnimation(reduceMotion ? nil : AppDesign.springAnimation) {
                contentVisible = true
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("白名单")
                .font(.system(size: 24, weight: .bold))

            Text("设置统计范围")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var overviewSection: some View {
        HStack(spacing: 14) {
            WhitelistCountCard(
                title: "应用",
                value: "\(whitelistManager.whitelistedApps.count)",
                detail: "自定义 \(customApps.count) 项",
                symbolName: "macwindow.on.rectangle",
                tint: AppDesign.primaryBlue
            )

            WhitelistCountCard(
                title: "域名",
                value: "\(whitelistManager.whitelistedDomains.count)",
                detail: "自定义 \(customDomains.count) 项",
                symbolName: "network",
                tint: AppDesign.websiteTeal
            )
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button(action: addAppFromFinder) {
                Label("添加应用", systemImage: "plus.app.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppCapsuleButtonStyle(role: .primary))

            Button(action: addDomainManually) {
                Label("添加域名", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppCapsuleButtonStyle(role: .primary))
        }
    }

    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("说明")
                .font(.system(size: 14, weight: .semibold))

            Text("浏览器记录需同时命中应用和域名白名单。")
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

    private func addAppFromFinder() {
        // 1. 创建并配置打开文件面板以允许选择应用程序。
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        // 2. 激活应用以保证面板显示在前台。
        NSApp.activate(ignoringOtherApps: true)

        // 3. 运行面板并在用户确认选择后提取应用名称并加入白名单。
        if panel.runModal() == .OK, let selectedAppUrl = panel.url {
            let appName = (selectedAppUrl.lastPathComponent as NSString).deletingPathExtension
            whitelistManager.addApp(appName)
        }
    }

    private func addDomainManually() {
        // 1. 创建并配置输入框及弹窗属性。
        let alert = NSAlert()
        alert.messageText = "添加域名"
        alert.informativeText = "例如：github.com"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        alert.accessoryView = inputField
        
        // 2. 将输入框作为附加视图载入弹窗并激活前台。
        NSApp.activate(ignoringOtherApps: true)
        
        // 3. 运行弹窗并在用户确认后将输入的域名整理并加入白名单。
        if alert.runModal() == .alertFirstButtonReturn {
            whitelistManager.addDomain(inputField.stringValue)
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

            WhitelistSectionBlock(
                title: defaultTitle,
                items: defaultItems,
                badgeText: "默认",
                badgeTint: tint.opacity(0.85),
                onDelete: onDelete
            )

            WhitelistSectionBlock(
                title: customTitle,
                items: customItems,
                badgeText: "自定义",
                badgeTint: AppDesign.primaryBlue.opacity(0.68),
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

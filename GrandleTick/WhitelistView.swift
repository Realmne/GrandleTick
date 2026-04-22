import SwiftUI

struct WhitelistView: View {
    @State private var manager = WhitelistManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // --- 固定在顶部的毛玻璃标题栏 ---
            HStack {
                Text("自定义白名单管理")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 28) // 避开红绿灯
            .padding(.bottom, 12)
            .background(Material.regular)
            .overlay(Divider(), alignment: .bottom)
            
            // --- 列表区域 ---
            List {
                Section(header: Text("默认应用").font(.headline)) {
                    ForEach(manager.whitelistedApps.filter { manager.systemDefaultApps.contains($0) }, id: \.self) { app in
                        AppRow(name: app) { manager.removeApp(app) }
                    }
                }
                
                Section(header: Text("用户自定义应用").font(.headline)) {
                    let customApps = manager.whitelistedApps.filter { !manager.systemDefaultApps.contains($0) }
                    if customApps.isEmpty {
                        Text("暂无自定义应用").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(customApps, id: \.self) { app in
                            AppRow(name: app) { manager.removeApp(app) }
                        }
                    }
                }
                
                Section(header: Text("默认域名 (需配合浏览器)").font(.headline)) {
                    ForEach(manager.whitelistedDomains.filter { manager.systemDefaultDomains.contains($0) }, id: \.self) { domain in
                        AppRow(name: domain) { manager.removeDomain(domain) }
                    }
                }
                
                Section(header: Text("用户自定义域名").font(.headline)) {
                    let customDomains = manager.whitelistedDomains.filter { !manager.systemDefaultDomains.contains($0) }
                    if customDomains.isEmpty {
                        Text("暂无自定义域名").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(customDomains, id: \.self) { domain in
                            AppRow(name: domain) { manager.removeDomain(domain) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            // --- 底部添加按钮 ---
            HStack(spacing: 20) {
                Button(action: addAppFromFinder) {
                    HStack {
                        Image(systemName: "macwindow.badge.plus")
                        Text("添加应用")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: addDomainManually) {
                    HStack {
                        Image(systemName: "link.badge.plus")
                        Text("添加域名")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 400, minHeight: 500)
        .ignoresSafeArea(.all, edges: .top) // 让头部完美贴合红绿灯
    }
    
    private func addAppFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        
        if panel.runModal() == .OK, let url = panel.url {
            let appName = (url.lastPathComponent as NSString).deletingPathExtension
            manager.addApp(appName)
        }
    }
    
    private func addDomainManually() {
        let alert = NSAlert()
        alert.messageText = "添加要追踪的域名"
        alert.informativeText = "请输入域名，例如: github.com"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        alert.accessoryView = inputField
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            manager.addDomain(inputField.stringValue)
        }
    }
}

struct AppRow: View {
    let name: String
    let onDelete: () -> Void
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

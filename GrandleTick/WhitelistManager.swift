import Foundation
import SwiftUI

@Observable
class WhitelistManager {
    static let shared = WhitelistManager()
    
    let systemDefaultApps = ["预览", "Safari", "Google Chrome", "Microsoft Edge"]
    let systemDefaultDomains = ["bilibili.com", "chatgpt.com", "openai.com", "doubao.com", "yuanbao.tencent.com", "gemini.google.com", "claude.ai", "deepseek.com"]
    let systemDefaultBlacklistApps: [String] = []
    let systemDefaultBlacklistDomains: [String] = []
    
    var whitelistedApps: [String] {
        didSet { UserDefaults.standard.set(whitelistedApps, forKey: "WhitelistedApps") }
    }
    
    var whitelistedDomains: [String] {
        didSet { UserDefaults.standard.set(whitelistedDomains, forKey: "WhitelistedDomains") }
    }

    var blacklistedApps: [String] {
        didSet { UserDefaults.standard.set(blacklistedApps, forKey: "BlacklistedApps") }
    }

    var blacklistedDomains: [String] {
        didSet { UserDefaults.standard.set(blacklistedDomains, forKey: "BlacklistedDomains") }
    }
    
    init() {
        // 1. 如果是首次启动，就写入默认的应用和域名白名单及黑名单配置。
        if UserDefaults.standard.object(forKey: "WhitelistedApps") == nil {
            UserDefaults.standard.set(systemDefaultApps, forKey: "WhitelistedApps")
        }
        if UserDefaults.standard.object(forKey: "WhitelistedDomains") == nil {
            UserDefaults.standard.set(systemDefaultDomains, forKey: "WhitelistedDomains")
        }
        if UserDefaults.standard.object(forKey: "BlacklistedApps") == nil {
            UserDefaults.standard.set(systemDefaultBlacklistApps, forKey: "BlacklistedApps")
        }
        if UserDefaults.standard.object(forKey: "BlacklistedDomains") == nil {
            UserDefaults.standard.set(systemDefaultBlacklistDomains, forKey: "BlacklistedDomains")
        }
        
        // 2. 如果用户已经有配置数据（或写入了默认数据），就将其加载到内存，保证运行时不覆盖现有配置。
        self.whitelistedApps = UserDefaults.standard.stringArray(forKey: "WhitelistedApps") ?? []
        self.whitelistedDomains = UserDefaults.standard.stringArray(forKey: "WhitelistedDomains") ?? []
        self.blacklistedApps = UserDefaults.standard.stringArray(forKey: "BlacklistedApps") ?? []
        self.blacklistedDomains = UserDefaults.standard.stringArray(forKey: "BlacklistedDomains") ?? []
    }
    
    // MARK: - 白名单管理（学习专注）

    func addApp(_ appName: String) {
        // 1. 若当前应用已在黑名单中，将其从黑名单中移除，保持白名单与黑名单互斥。
        blacklistedApps.removeAll { $0 == appName }

        // 2. 加入白名单并避免重复。
        if !whitelistedApps.contains(appName) {
            whitelistedApps.append(appName)
        }
    }
    
    func removeApp(_ appName: String) {
        whitelistedApps.removeAll { $0 == appName }
    }
    
    func addDomain(_ domain: String) {
        // 1. 规范化清洗用户输入的域名字符串。
        let cleaned = normalizeDomain(domain)
        guard !cleaned.isEmpty else { return }

        // 2. 从黑名单中移除该域名以保证互斥。
        blacklistedDomains.removeAll { $0 == cleaned }
        
        // 3. 校验并存入白名单。
        if !whitelistedDomains.contains(cleaned) {
            whitelistedDomains.append(cleaned)
        }
    }
    
    func removeDomain(_ domain: String) {
        whitelistedDomains.removeAll { $0 == domain }
    }

    // MARK: - 黑名单管理（娱乐休闲）

    func addBlacklistApp(_ appName: String) {
        // 1. 若当前应用已在白名单中，将其从白名单中移除，保证同一应用不会被双向分类。
        whitelistedApps.removeAll { $0 == appName }

        // 2. 加入黑名单并避免重复。
        if !blacklistedApps.contains(appName) {
            blacklistedApps.append(appName)
        }
    }

    func removeBlacklistApp(_ appName: String) {
        blacklistedApps.removeAll { $0 == appName }
    }

    func addBlacklistDomain(_ domain: String) {
        // 1. 规范化清洗用户输入的域名。
        let cleaned = normalizeDomain(domain)
        guard !cleaned.isEmpty else { return }

        // 2. 从白名单中移除该域名以保证互斥。
        whitelistedDomains.removeAll { $0 == cleaned }

        // 3. 校验并存入黑名单。
        if !blacklistedDomains.contains(cleaned) {
            blacklistedDomains.append(cleaned)
        }
    }

    func removeBlacklistDomain(_ domain: String) {
        blacklistedDomains.removeAll { $0 == domain }
    }

    // MARK: - 辅助方法

    private func normalizeDomain(_ domain: String) -> String {
        // 1. 去除首尾空格和换行
        var cleaned = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. 剥离常见的 URL 前缀
        if cleaned.hasPrefix("https://") {
            cleaned = String(cleaned.dropFirst(8))
        } else if cleaned.hasPrefix("http://") {
            cleaned = String(cleaned.dropFirst(7))
        }
        
        // 3. 剥离尾部的斜杠
        if cleaned.hasSuffix("/") {
            cleaned = String(cleaned.dropLast())
        }
        
        // 4. 剥离 www. 前缀，让匹配更通用
        if cleaned.hasPrefix("www.") {
            cleaned = String(cleaned.dropFirst(4))
        }

        return cleaned
    }
}

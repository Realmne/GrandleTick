import Foundation
import SwiftUI

@Observable
class WhitelistManager {
    static let shared = WhitelistManager()
    
    // 用于区分哪些是系统默认预设的，哪些是用户自定义的
    let systemDefaultApps = ["预览", "Safari", "Google Chrome", "Microsoft Edge"]
    let systemDefaultDomains = ["bilibili.com", "chatgpt.com", "openai.com", "doubao.com", "yuanbao.tencent.com", "gemini.google.com", "claude.ai", "deepseek.com"]
    
    var whitelistedApps: [String] {
        didSet { UserDefaults.standard.set(whitelistedApps, forKey: "WhitelistedApps") }
    }
    
    var whitelistedDomains: [String] {
        didSet { UserDefaults.standard.set(whitelistedDomains, forKey: "WhitelistedDomains") }
    }
    
    init() {
        // 如果是首次启动，写入默认数据
        if UserDefaults.standard.object(forKey: "WhitelistedApps") == nil {
            UserDefaults.standard.set(systemDefaultApps, forKey: "WhitelistedApps")
        }
        if UserDefaults.standard.object(forKey: "WhitelistedDomains") == nil {
            UserDefaults.standard.set(systemDefaultDomains, forKey: "WhitelistedDomains")
        }
        
        self.whitelistedApps = UserDefaults.standard.stringArray(forKey: "WhitelistedApps") ?? []
        self.whitelistedDomains = UserDefaults.standard.stringArray(forKey: "WhitelistedDomains") ?? []
    }
    
    func addApp(_ name: String) {
        if !whitelistedApps.contains(name) {
            whitelistedApps.append(name)
        }
    }
    
    func removeApp(_ name: String) {
        whitelistedApps.removeAll { $0 == name }
    }
    
    func addDomain(_ domain: String) {
        // 1. 去除首尾空格和换行
        var cleaned = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. 剥离常见的 URL 前缀
        if cleaned.hasPrefix("https://") {
            cleaned = String(cleaned.dropFirst(8)) // 删掉前8个字符
        } else if cleaned.hasPrefix("http://") {
            cleaned = String(cleaned.dropFirst(7)) // 删掉前7个字符
        }
        
        // 3. 剥离尾部的斜杠 (例如用户输入了 github.com/)
        if cleaned.hasSuffix("/") {
            cleaned = String(cleaned.dropLast())
        }
        
        // 4. (可选) 剥离 www. 前缀，让匹配更通用
        if cleaned.hasPrefix("www.") {
            cleaned = String(cleaned.dropFirst(4))
        }
        
        // 5. 校验并存入数据库
        if !whitelistedDomains.contains(cleaned) && !cleaned.isEmpty {
            whitelistedDomains.append(cleaned)
        }
    }
    
    func removeDomain(_ domain: String) {
        whitelistedDomains.removeAll { $0 == domain }
    }
}

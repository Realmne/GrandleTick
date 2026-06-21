import Foundation

struct BilibiliVideoMetadata: Sendable {
    let title: String
    let tidV2: Int
    let isKnowledge: Bool
}

enum BilibiliService {
    // 1. 从 URL 中提取视频标识符（BV 号或 EP 号）。
    static func extractIdentifier(from url: String) -> String? {
        let pattern = "(BV[a-zA-Z0-9]+|ep[0-9]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.utf16.count)) {
            let nsString = url as NSString
            return nsString.substring(with: match.range)
        }
        return nil
    }

    // 2. 通过 B 站 API 获取视频元数据。
    // 包括标题和分区 ID，用于判断视频是否属于知识类。
    static func fetchMetadata(for identifier: String) async -> BilibiliVideoMetadata? {
        // 1. 构建 B 站 Web View 接口请求 URL 并配置超时及 User-Agent。
        guard let url = URL(string: "\(AppConfig.bilibiliAPIUrl)\(identifier)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            // 2. 发起异步网络请求并解析 JSON 数据。
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(BilibiliViewResponse.self, from: data)

            guard response.code == 0, let responseData = response.data else {
                return nil
            }

            let tidV2 = responseData.tidV2 ?? responseData.tid
            let title = responseData.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            // 3. 提取分区 ID 并依据分区白名单判定是否为知识类视频。
            return BilibiliVideoMetadata(
                title: title,
                tidV2: tidV2,
                isKnowledge: AppConfig.bilibiliKnowledgeTidV2s.contains(tidV2)
            )
        } catch {
            print("[BilibiliService] 获取元数据失败: \(error.localizedDescription)")
            return nil
        }
    }
}

private struct BilibiliViewResponse: Decodable {
    let code: Int
    let data: BilibiliViewData?
}

private struct BilibiliViewData: Decodable {
    let tid: Int
    let tidV2: Int?
    let title: String

    enum CodingKeys: String, CodingKey {
        case tid
        case tidV2 = "tid_v2"
        case title
    }
}

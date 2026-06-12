import SwiftUI

struct ReportAppChampionPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let champion = snapshot.topApps.first {
                ReportHighlightCard(
                    title: champion.name,
                    value: formatDuration(champion.totalTime),
                    subtitle: "占总时长 \(Int((champion.share * 100).rounded()))%",
                    tint: .blue
                )
            }
            ReportRankingPanel(title: "用得最多的 3 个 App", items: snapshot.topApps, formatDuration: formatDuration)
        }
    }
}

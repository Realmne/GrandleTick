import SwiftUI

struct ReportSourcesPage: View {
    let snapshot: ReportSnapshot
    let formatDuration: (TimeInterval) -> String
    
    private var secondaryItems: [ReportRankItem] {
        snapshot.topPDFs.isEmpty ? snapshot.topItems : snapshot.topPDFs
    }
    
    private var secondaryTitle: String {
        snapshot.topPDFs.isEmpty ? "最常看的 3 个内容" : "最常看的 3 份 PDF"
    }
    
    var body: some View {
        let hasPrimary = !snapshot.topDomains.isEmpty
        let hasSecondary = !secondaryItems.isEmpty
        
        VStack(alignment: .leading, spacing: 20) {
            ReportContentCategoryCard(
                websiteDuration: snapshot.websiteDuration,
                pdfDuration: snapshot.pdfDuration,
                totalDuration: snapshot.totalDuration,
                formatDuration: formatDuration
            )
            .fadeInSlide(delay: 0.0)
            
            if hasPrimary && hasSecondary {
                HStack(alignment: .top, spacing: 18) {
                    ReportRankingPanel(title: "最常看的 3 个网站", items: snapshot.topDomains, formatDuration: formatDuration)
                        .fadeInSlide(delay: 0.1)
                    ReportRankingPanel(title: secondaryTitle, items: secondaryItems, formatDuration: formatDuration)
                        .fadeInSlide(delay: 0.15)
                }
            } else if hasPrimary {
                ReportRankingPanel(title: "最常看的 3 个网站", items: snapshot.topDomains, formatDuration: formatDuration)
                    .fadeInSlide(delay: 0.1)
            } else if hasSecondary {
                ReportRankingPanel(title: secondaryTitle, items: secondaryItems, formatDuration: formatDuration)
                    .fadeInSlide(delay: 0.1)
            } else {
                ReportPlaceholderCard(title: "这段时间还没有足够的内容记录", subtitle: "有了网站或 PDF 记录后，这一页会自动补全。")
                    .fadeInSlide(delay: 0.1)
            }
        }
    }
}

import SwiftUI
import SwiftData
import Charts

struct ReportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var engine = ReportEngine()
    @State private var whitelist = WhitelistManager.shared
    @State private var selectedPeriod: ReportPeriod = .week
    @State private var selectedReferenceDate = Date()
    @State private var selectedPage: ReportPage = .cover

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            backgroundGradient
            contentLayer
        }
        .frame(minWidth: AppConfig.reportMinWidth, minHeight: AppConfig.reportMinHeight)
        .transaction { $0.animation = nil }
        .onAppear(perform: refreshSnapshot)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in refreshSnapshot() }
        .onChange(of: whitelist.whitelistedApps) { _, _ in refreshSnapshot() }
        .onChange(of: whitelist.whitelistedDomains) { _, _ in refreshSnapshot() }
        .onChange(of: selectedPeriod) { _, _ in refreshSnapshot() }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.96, blue: 0.92),
                Color(red: 0.93, green: 0.96, blue: 0.98),
                Color(red: 0.98, green: 0.95, blue: 0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var contentLayer: some View {
        VStack(spacing: 0) {
            if let snapshot = engine.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if snapshot.hasData {
                            headerSection(for: snapshot)
                            pageSection(for: snapshot)
                        } else {
                            emptyStateView(for: snapshot)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func headerSection(for snapshot: ReportSnapshot) -> some View {
        ReportPageHeader(
            selectedPeriod: $selectedPeriod,
            rangeText: ReportFormatter.formatDateRange(snapshot.interval, calendar: calendar),
            canShowPreviousPeriod: engine.canShowPreviousPeriod,
            canShowNextPeriod: canShowNextPeriod,
            previousPeriod: showPreviousPeriod,
            nextPeriod: showNextPeriod,
            label: selectedPage.label,
            title: pageTitle(for: snapshot),
            subtitle: pageSubtitle(for: snapshot),
            pager: AnyView(headerPager)
        )
    }

    @ViewBuilder
    private func pageSection(for snapshot: ReportSnapshot) -> some View {
        switch selectedPage {
        case .cover:
            ReportCoverPage(
                snapshot: snapshot,
                formatDuration: ReportFormatter.formatDetailedDuration,
                formatDateRange: { ReportFormatter.formatDateRange($0, calendar: calendar) }
            )
        case .appChampion:
            ReportAppChampionPage(
                snapshot: snapshot,
                formatDuration: ReportFormatter.formatCompactDuration
            )
        case .sources:
            ReportSourcesPage(
                snapshot: snapshot,
                formatDuration: ReportFormatter.formatCompactDuration
            )
        case .peakDay:
            ReportPeakDayPage(
                snapshot: snapshot,
                formatDuration: ReportFormatter.formatCompactDuration,
                formatDay: { ReportFormatter.formatLongDate($0, calendar: calendar) }
            )
        case .rhythm:
            ReportRhythmPage(
                snapshot: snapshot,
                formatDuration: ReportFormatter.formatCompactDuration,
                formatDay: { ReportFormatter.formatShortDate($0, calendar: calendar) },
                formatLongDay: { ReportFormatter.formatLongDate($0, calendar: calendar) },
                formatClock: ReportFormatter.formatClock
            )
        }
    }

    private func pageTitle(for snapshot: ReportSnapshot) -> String {
        switch selectedPage {
        case .cover: return snapshot.period.reportTitle
        case .appChampion: return snapshot.topApps.first.map { "热度最高的 App 是 \($0.name)" } ?? "热度最高 App"
        case .sources: return "这段时间你主要在看什么"
        case .peakDay: return snapshot.strongestDay.map { "\(ReportFormatter.formatLongDate($0.date, calendar: calendar)) 是你学得最久的一天" } ?? "高峰日"
        case .rhythm: return "学习节奏"
        }
    }

    private func pageSubtitle(for snapshot: ReportSnapshot) -> String? {
        switch selectedPage {
        case .cover: return nil
        case .appChampion: return snapshot.topApps.isEmpty ? nil : snapshot.appFocusSummary
        case .sources: return "网站和 PDF 会放在一起看"
        case .peakDay: return snapshot.strongestDay.map { "这一天一共学了 \(ReportFormatter.formatCompactDuration($0.totalTime))" }
        case .rhythm: return "看看你通常在什么时间进入状态"
        }
    }

    private var headerPager: some View {
        HStack(spacing: 10) {
            ReportPagerButton(systemImage: "chevron.left", isDisabled: selectedPage == .cover, action: showPreviousPage)
            ReportPagerButton(systemImage: "chevron.right", isDisabled: selectedPage == .rhythm, action: showNextPage)
        }
    }

    private var canShowNextPeriod: Bool {
        let now = Date()
        let selectedInterval = selectedPeriod.reportInterval(containing: selectedReferenceDate, currentDate: now, calendar: calendar)
        let currentInterval = selectedPeriod.reportInterval(containing: now, currentDate: now, calendar: calendar)
        return selectedInterval.start < currentInterval.start
    }

    private func emptyStateView(for snapshot: ReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ReportPageHeader(
                selectedPeriod: $selectedPeriod,
                rangeText: ReportFormatter.formatDateRange(snapshot.interval, calendar: calendar),
                canShowPreviousPeriod: engine.canShowPreviousPeriod,
                canShowNextPeriod: canShowNextPeriod,
                previousPeriod: showPreviousPeriod,
                nextPeriod: showNextPeriod,
                label: "总览",
                title: snapshot.period.reportTitle,
                subtitle: nil,
                pager: AnyView(EmptyView())
            )

            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "book.closed.circle").font(.system(size: 46, weight: .light)).foregroundColor(.secondary.opacity(0.45))
                Text("\(selectedPeriod.title)还没有学习记录").font(.system(size: 22, weight: .bold))
                Text("切换到白名单内的应用或网站后，这里会自动整理出 5 页回顾。").font(.callout).foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 440)
        }
    }

    private func refreshSnapshot() { engine.refreshSnapshot(period: selectedPeriod, referenceDate: selectedReferenceDate, modelContext: modelContext, whitelist: whitelist) }
    private func showPreviousPeriod() { guard engine.canShowPreviousPeriod else { return }; shiftSelectedPeriod(by: -1) }
    private func showNextPeriod() { guard canShowNextPeriod else { return }; shiftSelectedPeriod(by: 1) }
    private func shiftSelectedPeriod(by value: Int) { guard let nextDate = calendar.date(byAdding: reportCalendarComponent, value: value, to: selectedReferenceDate) else { return }; selectedReferenceDate = nextDate; refreshSnapshot() }
    private var reportCalendarComponent: Calendar.Component { switch selectedPeriod { case .week: return .weekOfYear; case .month: return .month; case .year: return .year } }
    private func showPreviousPage() { guard let previous = ReportPage(rawValue: selectedPage.rawValue - 1) else { return }; selectedPage = previous }
    private func showNextPage() { guard let next = ReportPage(rawValue: selectedPage.rawValue + 1) else { return }; selectedPage = next }
}

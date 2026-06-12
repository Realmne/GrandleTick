import SwiftUI

struct ReportPageHeader: View {
    @Binding var selectedPeriod: ReportPeriod
    let rangeText: String
    let canShowPreviousPeriod: Bool
    let canShowNextPeriod: Bool
    let previousPeriod: () -> Void
    let nextPeriod: () -> Void
    let label: String
    let title: String
    let subtitle: String?
    let pager: AnyView
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                HStack(spacing: 10) {
                    Text("报告周期")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Picker("报告周期", selection: $selectedPeriod) {
                        ForEach(ReportPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    ReportPagerButton(
                        systemImage: "chevron.left",
                        isDisabled: !canShowPreviousPeriod,
                        action: previousPeriod
                    )
                    
                    Text(rangeText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 96)
                    
                    ReportPagerButton(
                        systemImage: "chevron.right",
                        isDisabled: !canShowNextPeriod,
                        action: nextPeriod
                    )
                }
                
                pager
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.title3.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28).fill(Color.white.opacity(0.46)))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.65), lineWidth: 1))
    }
}

import SwiftUI

struct MetricTile: View {
    let eyebrow: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(eyebrow.uppercased(), systemImage: symbol)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }

            Text(value)
                .font(.system(size: 27, weight: .semibold, design: .monospaced))
                .foregroundStyle(LittleWatchTheme.primaryText)
                .contentTransition(.numericText())

            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(LittleWatchTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentCard()
    }
}

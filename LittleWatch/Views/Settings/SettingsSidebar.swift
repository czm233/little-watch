import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case menuBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: "顶部栏"
        }
    }

    var symbol: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        }
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 28)

            Text("WORKSPACE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.35)
                .foregroundStyle(LittleWatchTheme.secondaryText.opacity(0.75))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol)
                            .frame(width: 17)
                        Text(section.title)
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        selection == section
                            ? LittleWatchTheme.primaryText
                            : LittleWatchTheme.secondaryText
                    )
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selection == section ? Color.white.opacity(0.075) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .frame(width: 190)
        .background(LittleWatchTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(LittleWatchTheme.hairline)
                .frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LittleWatchTheme.signal)
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LittleWatchTheme.sidebar)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("Little Watch")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text("MENUBAR TELEMETRY")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }
        }
    }
}

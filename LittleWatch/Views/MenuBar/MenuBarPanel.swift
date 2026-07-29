import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var store: AppStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 10) {
                MetricTile(
                    eyebrow: "本期消费",
                    value: MenuBarFormatter().formatCost(
                        store.snapshot.costUSD,
                        precision: store.configuration.costPrecision
                    ),
                    detail: "今日累计用量",
                    symbol: "dollarsign"
                )

                MetricTile(
                    eyebrow: "Token 消耗",
                    value: store.snapshot.tokenCount.formatted(),
                    detail: realtimeDetail,
                    symbol: "number"
                )

                systemMetrics
            }
            .padding(14)

            Divider().overlay(LittleWatchTheme.hairline)

            footer
        }
        .frame(width: 340)
        .background(LittleWatchTheme.canvas)
        .preferredColorScheme(.dark)
    }

    private var systemMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本机状态", systemImage: "desktopcomputer")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
                Spacer()
                Text(store.systemSnapshot.updatedAt == .distantPast ? "采集中" : "每 5 秒更新")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText.opacity(0.72))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                SystemMetricCell(
                    title: "CPU",
                    value: percent(store.systemSnapshot.cpuUsagePercent),
                    progress: store.systemSnapshot.cpuUsagePercent
                )
                SystemMetricCell(
                    title: "内存",
                    value: percent(store.systemSnapshot.memoryUsagePercent),
                    progress: store.systemSnapshot.memoryUsagePercent
                )
                SystemMetricCell(
                    title: "磁盘",
                    value: percent(store.systemSnapshot.diskUsagePercent),
                    progress: store.systemSnapshot.diskUsagePercent
                )
                SystemMetricCell(
                    title: "剩余空间",
                    value: diskFree(store.systemSnapshot.diskFreeBytes),
                    progress: store.systemSnapshot.diskUsagePercent
                )
            }
        }
        .padding(12)
        .background(LittleWatchTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LittleWatchTheme.hairline, lineWidth: 1)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func diskFree(_ bytes: Int64) -> String {
        MenuBarFormatter().formatDiskFree(bytes).replacingOccurrences(of: "FREE ", with: "")
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LittleWatchTheme.signal.opacity(0.12))
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LittleWatchTheme.signal)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("LITTLE WATCH")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.25)
                    .foregroundStyle(LittleWatchTheme.primaryText)

                HStack(spacing: 5) {
                    Circle()
                        .fill(store.isSourceConnected ? LittleWatchTheme.signal : LittleWatchTheme.amber)
                        .frame(width: 5, height: 5)
                    Text("\(store.sourceName) · \(store.connectionStatusText)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.secondaryText)
                }
            }

            Spacer()

            Text(store.snapshot.updatedAt, style: .time)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(LittleWatchTheme.secondaryText)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.refresh() }
            } label: {
                Label(refreshLabel, systemImage: "arrow.clockwise")
                    .contentShape(Rectangle())
            }
            .disabled(isRefreshing)
            .allowsHitTesting(!isRefreshing)
            .opacity(isRefreshing ? 0.38 : 1)
            .focusable(false)

            Spacer()

            Button(action: showSettings) {
                Label("配置", systemImage: "slider.horizontal.3")
                    .contentShape(Rectangle())
            }
            .focusable(false)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .contentShape(Rectangle())
            }
            .help("退出 Little Watch")
            .focusable(false)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(LittleWatchTheme.secondaryText)
        .padding(14)
    }

    private var refreshLabel: String {
        isRefreshing ? "刷新中" : "刷新"
    }

    private var isRefreshing: Bool {
        store.refreshState == .refreshing
    }

    private var realtimeDetail: String {
        guard let tpm = store.snapshot.tokensPerMinute else {
            return "今日累计 Token"
        }
        let value = tpm.formatted(.number.precision(.fractionLength(0...1)))
        return "实时 \(value) TPM"
    }

    private func showSettings() {
        openSettings()

        Task { @MainActor in
            // The settings scene can be created after the menu-bar panel closes,
            // so retry briefly before bringing it to the foreground.
            for attempt in 0..<6 {
                if let window = settingsWindow {
                    moveOnScreenIfNeeded(window)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    return
                }

                if attempt < 5 {
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        }
    }

    @MainActor
    private var settingsWindow: NSWindow? {
        NSApplication.shared.windows.first { window in
            window.title == "Little Watch Settings"
                || (window.styleMask.contains(.titled)
                    && window.canBecomeKey
                    && !(window is NSPanel))
        }
    }

    @MainActor
    private func moveOnScreenIfNeeded(_ window: NSWindow) {
        let isOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(window.frame)
        }

        if !isOnScreen {
            window.center()
        }
    }
}

private struct SystemMetricCell: View {
    let title: String
    let value: String
    let progress: Double

    private var tint: Color {
        switch progress {
        case 80...: Color(red: 1.0, green: 0.36, blue: 0.32)
        case 60...: LittleWatchTheme.amber
        default: LittleWatchTheme.signal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(LittleWatchTheme.primaryText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(progress / 100, 0), 1))
                }
            }
            .frame(height: 3)
        }
        .padding(9)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

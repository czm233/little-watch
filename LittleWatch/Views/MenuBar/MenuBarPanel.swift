import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var store: AppStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SourceSetupOnboarding.completionKey) private var hasCompletedSourceSetup = false

    init(store: AppStore) {
        self.store = store
        let hasCompletedSourceSetup = SourceSetupOnboarding.bootstrap(for: store)
        _hasCompletedSourceSetup = AppStorage(
            wrappedValue: hasCompletedSourceSetup,
            SourceSetupOnboarding.completionKey
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if hasCompletedSourceSetup {
                VStack(spacing: 10) {
                    MetricTile(
                        eyebrow: "本期消费",
                        value: MenuBarFormatter().formatCost(
                            store.snapshot.costUSD,
                            precision: store.configuration.costPrecision
                        ),
                        detail: costDetail,
                        symbol: "dollarsign"
                    )

                    MetricTile(
                        eyebrow: "Token 消耗",
                        value: store.snapshot.tokenCount.formatted(),
                        detail: realtimeDetail,
                        symbol: "number"
                    )

                    systemMetrics

                    quotaSummary

                    if let spike = store.snapshot.usageSpike {
                        HStack(spacing: 9) {
                            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                                .foregroundStyle(LittleWatchTheme.amber)
                            Text(spikeSummary(spike))
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(LittleWatchTheme.secondaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(LittleWatchTheme.amber.opacity(0.055))
                        )
                    }
                }
                .padding(14)
            } else {
                firstRunSetup
                    .padding(14)
            }

            Divider().overlay(LittleWatchTheme.hairline)

            footer
        }
        .frame(width: 340)
        .background(LittleWatchTheme.canvas)
        .preferredColorScheme(.dark)
    }

    private var firstRunSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LittleWatchTheme.signal.opacity(0.12))
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LittleWatchTheme.signal)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text("完成首次配置")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.primaryText)
                    Text("连接 CPA Usage Keeper 后开始显示用量")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.secondaryText)
                }
            }

            HStack(spacing: 7) {
                setupHint("1", "服务地址")
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LittleWatchTheme.secondaryText.opacity(0.55))
                setupHint("2", "登录密码")
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LittleWatchTheme.secondaryText.opacity(0.55))
                setupHint("3", "连接验证")
            }

            Button(action: showSettings) {
                HStack {
                    Text("打开数据源配置")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(LittleWatchTheme.sidebar)
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LittleWatchTheme.signal)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(LittleWatchTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LittleWatchTheme.signal.opacity(0.17), lineWidth: 1)
        }
    }

    private func setupHint(_ index: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Text(index)
                .foregroundStyle(LittleWatchTheme.signal)
            Text(title)
                .foregroundStyle(LittleWatchTheme.secondaryText)
        }
        .font(.system(size: 8.5, weight: .bold, design: .rounded))
    }

    private var systemMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本机状态", systemImage: "desktopcomputer")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
                Spacer()
                Text(store.systemSnapshot.updatedAt == .distantPast ? "采集中" : "CPU/内存 5 秒 · 磁盘 5 分钟")
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

    private var quotaSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LittleWatchTheme.signal)

            VStack(alignment: .leading, spacing: 3) {
                Text("Weekly 剩余额度")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
                Text(store.quotaRemainingPercent.map {
                    "\(Int($0.rounded()))%"
                } ?? "—")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(LittleWatchTheme.signal)
            }

            Spacer()

            Text(store.quotaLastUpdatedText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(LittleWatchTheme.secondaryText)
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

            Button {
                Task { await store.refreshQuota() }
            } label: {
                Label(
                    store.quotaRefreshButtonLabel,
                    systemImage: "gauge.with.dots.needle.67percent"
                )
                .contentShape(Rectangle())
            }
            .disabled(!store.canRefreshQuota)
            .opacity(store.canRefreshQuota ? 1 : 0.38)
            .help(store.quotaRefreshStatusDetail)
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

    private var costDetail: String {
        let forecast = store.snapshot.projectedEndOfDayCostUSD.map {
            "预计日终 \(MenuBarFormatter().formatCost($0, precision: store.configuration.costPrecision))"
        }
        guard let budget = store.alertConfiguration.normalizedDailyBudgetUSD else {
            return forecast ?? "今日累计用量"
        }
        let percent = Int((store.snapshot.costUSD / budget * 100).rounded())
        if let forecast {
            return "预算已用 \(percent)% · \(forecast)"
        }
        return "每日预算 \(MenuBarFormatter().formatCost(budget, precision: store.configuration.costPrecision)) · 已用 \(percent)%"
    }

    private func spikeSummary(_ spike: UsageSpikeEvent) -> String {
        let metric = spike.metric == .tokensPerMinute ? "TPM" : "RPM"
        let multiple = spike.multiple.formatted(.number.precision(.fractionLength(1)))
        return "\(metric) 突增，约为近期基线的 \(multiple) 倍"
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

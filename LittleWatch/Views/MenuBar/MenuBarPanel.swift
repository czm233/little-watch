import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var store: AppStore
    @Environment(\.openSettings) private var openSettings
    @State private var isManualRefreshing = false
    @State private var showsRefreshConfirmation = false
    @State private var showsQuotaConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 10) {
                if store.hasConfiguredSource {
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
                }

                systemMetrics

                if store.hasConfiguredSource {
                    quotaSummary
                }

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

            VStack(alignment: .trailing, spacing: 3) {
                Text("重置 \(store.quotaResetDateText)")
                if !store.quotaResetRelativeText.isEmpty {
                    Text(store.quotaResetRelativeText)
                }
                Text(store.quotaLastUpdatedText)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(LittleWatchTheme.secondaryText)
            .multilineTextAlignment(.trailing)
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
                        .fill(
                            store.hasConfiguredSource && !store.isSourceConnected
                                ? LittleWatchTheme.amber
                                : LittleWatchTheme.signal
                        )
                        .frame(width: 5, height: 5)
                    Text(
                        store.hasConfiguredSource
                            ? "\(store.sourceName) · \(store.connectionStatusText)"
                            : "本机状态"
                    )
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
            Button(action: refreshNow) {
                HStack(spacing: 4) {
                    Image(systemName: showsRefreshConfirmation ? "checkmark" : "arrow.clockwise")
                        .rotationEffect(.degrees(isManualRefreshing ? 360 : 0))
                        .animation(
                            isManualRefreshing
                                ? .linear(duration: 0.7).repeatForever(autoreverses: false)
                                : .easeOut(duration: 0.2),
                            value: isManualRefreshing
                        )
                    Text(refreshLabel)
                }
                .foregroundStyle(
                    showsRefreshConfirmation
                        ? LittleWatchTheme.signal
                        : LittleWatchTheme.secondaryText
                )
                .contentShape(Rectangle())
            }
            .disabled(isManualRefreshing || isRefreshing)
            .allowsHitTesting(!isManualRefreshing && !isRefreshing)
            .opacity(isRefreshing ? 0.38 : (isManualRefreshing ? 0.7 : 1))
            .focusable(false)

            Button {
                Task { await store.refreshQuota() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showsQuotaConfirmation ? "checkmark" : "gauge.with.dots.needle.67percent")
                        .rotationEffect(.degrees(isQuotaRefreshing ? 360 : 0))
                        .animation(
                            isQuotaRefreshing
                                ? .linear(duration: 0.7).repeatForever(autoreverses: false)
                                : .easeOut(duration: 0.2),
                            value: isQuotaRefreshing
                        )
                    Text(quotaLabel)
                }
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
        .buttonStyle(FooterButtonStyle())
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(LittleWatchTheme.secondaryText)
        .padding(14)
        .onChange(of: store.quotaRefreshState) { _, newState in
            if case .succeeded = newState {
                showsQuotaConfirmation = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1600))
                    showsQuotaConfirmation = false
                }
            }
        }
    }

    private var refreshLabel: String {
        if isManualRefreshing { return "刷新中" }
        if showsRefreshConfirmation { return "已刷新" }
        return "刷新"
    }

    private var quotaLabel: String {
        if showsQuotaConfirmation { return "已更新" }
        return store.quotaRefreshButtonLabel
    }

    private var isQuotaRefreshing: Bool {
        if case .refreshing = store.quotaRefreshState { return true }
        return false
    }

    private func refreshNow() {
        guard !isManualRefreshing else { return }
        isManualRefreshing = true

        Task { @MainActor in
            let startedAt = Date()
            await store.refresh()
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed < 0.6 {
                try? await Task.sleep(for: .milliseconds(Int((0.6 - elapsed) * 1000)))
            }
            isManualRefreshing = false
            showsRefreshConfirmation = true
            try? await Task.sleep(for: .milliseconds(1600))
            showsRefreshConfirmation = false
        }
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

private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.white.opacity(0.16)
                            : Color.white.opacity(0.05)
                    )
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

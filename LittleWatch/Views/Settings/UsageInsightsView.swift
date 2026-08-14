import AppKit
import SwiftUI

struct UsageInsightsView: View {
    @ObservedObject var store: AppStore
    @State private var budgetText = ""
    @State private var budgetValidationMessage: String?
    @State private var isResetConfirmationPresented = false
    @FocusState private var isBudgetFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                overview
                alertSettings
                trends
                spikeStatus
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .onAppear {
            syncBudgetText()
            Task { await store.refreshNotificationPermissionState() }
        }
        .onChange(of: isBudgetFocused) { _, isFocused in
            if !isFocused { saveBudget() }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("用量与提醒")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text("把今日消费、实时趋势和需要处理的异常放在一起。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("分层刷新")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(LittleWatchTheme.signal)
                Text("累计 60 秒 · 实时 10 秒")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageSectionLabel(index: "01", title: "今日进度", detail: "预算与预测")

            HStack(spacing: 12) {
                UsageSummaryCard(
                    label: "今日消费",
                    value: currency(store.snapshot.costUSD),
                    detail: budgetDetail,
                    symbol: "dollarsign",
                    color: budgetStateColor,
                    progress: budgetProgress
                )

                UsageSummaryCard(
                    label: "预计日终",
                    value: store.snapshot.projectedEndOfDayCostUSD.map(currency) ?? "—",
                    detail: projectionDetail,
                    symbol: "chart.line.uptrend.xyaxis",
                    color: LittleWatchTheme.cyan,
                    progress: nil
                )
            }

            HStack(spacing: 12) {
                settingSymbol("arrow.counterclockwise", color: LittleWatchTheme.cyan)

                VStack(alignment: .leading, spacing: 3) {
                    Text("统计起点")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.primaryText)
                    Text(store.dailyUsageCounterReset.map {
                        "已从 \($0.resetAt.formatted(date: .omitted, time: .shortened)) 重新计数"
                    } ?? "如果服务端额度刚重置，可从当前值重新开始")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.secondaryText)
                }

                Spacer()

                Button("重置今日计数") {
                    isResetConfirmationPresented = true
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LittleWatchTheme.signal)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .instrumentCard()
            .alert("重置今日计数？", isPresented: $isResetConfirmationPresented) {
                Button("取消", role: .cancel) {}
                Button("从 0 开始", role: .destructive) {
                    store.resetDailyUsageCounter()
                }
            } message: {
                Text("当前今日消费、Token 和请求数会作为新的统计起点。不会删除服务端数据，也不会影响额度刷新。")
            }
        }
    }

    private var alertSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageSectionLabel(index: "02", title: "提醒规则", detail: "只在需要时打扰")

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    settingSymbol("target", color: LittleWatchTheme.amber)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("每日预算")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LittleWatchTheme.primaryText)
                        Text(budgetValidationMessage ?? "达到预算后每天最多提醒一次")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(budgetValidationMessage == nil ? LittleWatchTheme.secondaryText : Color.red.opacity(0.85))
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("$")
                            .foregroundStyle(LittleWatchTheme.secondaryText)
                        TextField("例如 20", text: $budgetText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .focused($isBudgetFocused)
                            .onSubmit(saveBudget)
                            .frame(width: 82)
                        Button("保存", action: saveBudget)
                            .buttonStyle(.borderless)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(LittleWatchTheme.signal)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 62)

                settingsDivider

                alertToggleRow(
                    title: "预算超限提醒",
                    detail: store.alertConfiguration.normalizedDailyBudgetUSD == nil
                        ? "请先设置有效的每日预算"
                        : "今日消费首次达到预算时发送通知",
                    symbol: "bell.badge.fill",
                    color: LittleWatchTheme.amber,
                    isOn: Binding(
                        get: { store.alertConfiguration.budgetAlertEnabled },
                        set: { setAlertEnabled($0, keyPath: \UsageAlertConfiguration.budgetAlertEnabled) }
                    ),
                    isDisabled: store.alertConfiguration.normalizedDailyBudgetUSD == nil
                )

                settingsDivider

                alertToggleRow(
                    title: "用量突增提醒",
                    detail: "TPM 或 RPM 达到近期基线 2 倍时提醒",
                    symbol: "waveform.path.ecg",
                    color: Color(red: 1.0, green: 0.42, blue: 0.34),
                    isOn: Binding(
                        get: { store.alertConfiguration.spikeAlertEnabled },
                        set: { setAlertEnabled($0, keyPath: \UsageAlertConfiguration.spikeAlertEnabled) }
                    )
                )

                if notificationsAreRelevant {
                    settingsDivider
                    notificationStatus
                }
            }
            .instrumentCard()
        }
    }

    private var trends: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageSectionLabel(index: "03", title: "最近 60 分钟", detail: "TPM / RPM 趋势")

            HStack(alignment: .top, spacing: 12) {
                RateTrendCard(
                    title: "TPM",
                    subtitle: "每分钟 Token",
                    points: store.snapshot.tokensPerMinuteTrend,
                    color: LittleWatchTheme.signal
                )
                RateTrendCard(
                    title: "RPM",
                    subtitle: "每分钟请求",
                    points: store.snapshot.requestsPerMinuteTrend,
                    color: LittleWatchTheme.cyan
                )
            }
        }
    }

    private var spikeStatus: some View {
        HStack(spacing: 14) {
            settingSymbol(
                store.snapshot.usageSpike == nil ? "checkmark.circle.fill" : "bolt.trianglebadge.exclamationmark.fill",
                color: store.snapshot.usageSpike == nil ? LittleWatchTheme.signal : LittleWatchTheme.amber
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(store.snapshot.usageSpike == nil ? "当前未检测到用量突增" : "检测到实时用量突增")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text(spikeDetail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((store.snapshot.usageSpike == nil ? LittleWatchTheme.signal : LittleWatchTheme.amber).opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke((store.snapshot.usageSpike == nil ? LittleWatchTheme.signal : LittleWatchTheme.amber).opacity(0.13), lineWidth: 1)
                }
        )
    }

    private func alertToggleRow(
        title: String,
        detail: String,
        symbol: String,
        color: Color,
        isOn: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            settingSymbol(symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }

    private var notificationStatus: some View {
        HStack(spacing: 14) {
            settingSymbol(permissionSymbol, color: permissionColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("系统通知")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text(permissionDetail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }
            Spacer()
            if store.notificationPermissionState == .denied {
                Button("打开系统设置") {
                    openNotificationSettings()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LittleWatchTheme.signal)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private func settingSymbol(_ symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color.opacity(0.11))
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 34, height: 34)
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(LittleWatchTheme.hairline)
            .padding(.leading, 64)
    }

    private var notificationsAreRelevant: Bool {
        store.alertConfiguration.budgetAlertEnabled || store.alertConfiguration.spikeAlertEnabled
    }

    private func setAlertEnabled(
        _ isEnabled: Bool,
        keyPath: WritableKeyPath<UsageAlertConfiguration, Bool>
    ) {
        store.alertConfiguration[keyPath: keyPath] = isEnabled
        if isEnabled, store.notificationPermissionState != .authorized {
            Task { await store.requestNotificationPermission() }
        }
    }

    private func saveBudget() {
        let trimmed = budgetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            store.alertConfiguration.dailyBudgetUSD = nil
            store.alertConfiguration.budgetAlertEnabled = false
            budgetValidationMessage = nil
            return
        }

        guard let value = Double(trimmed), value.isFinite, value > 0 else {
            budgetValidationMessage = "请输入大于 0 的金额"
            return
        }

        store.alertConfiguration.dailyBudgetUSD = value
        budgetText = value.formatted(.number.precision(.fractionLength(0...2)))
        budgetValidationMessage = nil
    }

    private func syncBudgetText() {
        budgetText = store.alertConfiguration.normalizedDailyBudgetUSD?.formatted(
            .number.precision(.fractionLength(0...2))
        ) ?? ""
    }

    private var budgetProgress: Double? {
        guard let budget = store.alertConfiguration.normalizedDailyBudgetUSD else { return nil }
        return min(max(store.snapshot.costUSD / budget, 0), 1)
    }

    private var budgetDetail: String {
        guard let budget = store.alertConfiguration.normalizedDailyBudgetUSD else {
            return "尚未设置每日预算"
        }
        let percent = Int((store.snapshot.costUSD / budget * 100).rounded())
        return "预算 \(currency(budget)) · 已使用 \(percent)%"
    }

    private var projectionDetail: String {
        guard
            let projected = store.snapshot.projectedEndOfDayCostUSD,
            let budget = store.alertConfiguration.normalizedDailyBudgetUSD
        else {
            return store.snapshot.projectedEndOfDayCostUSD == nil
                ? "等待今日累计数据"
                : "按当前平均速度估算"
        }
        return projected > budget ? "预计超出预算 \(currency(projected - budget))" : "预计仍在预算内"
    }

    private var budgetStateColor: Color {
        guard let budget = store.alertConfiguration.normalizedDailyBudgetUSD else { return LittleWatchTheme.amber }
        return store.snapshot.costUSD >= budget ? Color.red.opacity(0.85) : LittleWatchTheme.amber
    }

    private var spikeDetail: String {
        guard let spike = store.snapshot.usageSpike else {
            return "以最近至少 5 个采样点为基线，持续观察 TPM 与 RPM。"
        }
        let metric = spike.metric == .tokensPerMinute ? "TPM" : "RPM"
        let current = spike.currentValue.formatted(.number.precision(.fractionLength(0...1)))
        let multiple = spike.multiple.formatted(.number.precision(.fractionLength(1)))
        return "\(metric) 当前为 \(current)，约是近期基线的 \(multiple) 倍。"
    }

    private var permissionSymbol: String {
        switch store.notificationPermissionState {
        case .authorized: "bell.fill"
        case .denied: "bell.slash.fill"
        case .unknown: "bell.badge"
        }
    }

    private var permissionColor: Color {
        switch store.notificationPermissionState {
        case .authorized: LittleWatchTheme.signal
        case .denied: LittleWatchTheme.amber
        case .unknown: LittleWatchTheme.cyan
        }
    }

    private var permissionDetail: String {
        switch store.notificationPermissionState {
        case .authorized: "通知已授权，提醒规则可以正常发送"
        case .denied: "通知已关闭，需要在系统设置中允许 Little Watch"
        case .unknown: "开启提醒时将请求 macOS 通知权限"
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

private struct UsageSummaryCard: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(label, systemImage: symbol)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(LittleWatchTheme.secondaryText)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.55), radius: 4)
            }

            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(LittleWatchTheme.primaryText)
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 7) {
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
                if let progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule()
                                .fill(color)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
        .instrumentCard()
    }
}

private struct RateTrendCard: View {
    let title: String
    let subtitle: String
    let points: [UsageRatePoint]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(color)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.secondaryText)
                }
                Spacer()
                Text(currentValue)
                    .font(.system(size: 21, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LittleWatchTheme.primaryText)
            }

            if points.count >= 2 {
                Sparkline(points: points, color: color)
                    .frame(height: 92)
                HStack {
                    Text(points.first?.timestamp.formatted(date: .omitted, time: .shortened) ?? "")
                    Spacer()
                    Text(points.last?.timestamp.formatted(date: .omitted, time: .shortened) ?? "")
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(LittleWatchTheme.secondaryText.opacity(0.72))
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 18, weight: .light))
                    Text("等待实时趋势数据")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundStyle(LittleWatchTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 108)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentCard()
    }

    private var currentValue: String {
        points.last?.value.formatted(.number.precision(.fractionLength(0...1))) ?? "—"
    }
}

private struct Sparkline: View {
    let points: [UsageRatePoint]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack {
                    Divider().overlay(Color.white.opacity(0.045))
                    Spacer()
                    Divider().overlay(Color.white.opacity(0.045))
                    Spacer()
                    Divider().overlay(Color.white.opacity(0.045))
                }

                areaPath(in: proxy.size)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.20), color.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                linePath(in: proxy.size)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func linePath(in size: CGSize) -> Path {
        let coordinates = normalizedCoordinates(in: size)
        return Path { path in
            guard let first = coordinates.first else { return }
            path.move(to: first)
            for point in coordinates.dropFirst() { path.addLine(to: point) }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        let coordinates = normalizedCoordinates(in: size)
        return Path { path in
            guard let first = coordinates.first, let last = coordinates.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in coordinates.dropFirst() { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }

    private func normalizedCoordinates(in size: CGSize) -> [CGPoint] {
        let ordered = points.sorted { $0.timestamp < $1.timestamp }
        guard let first = ordered.first, let last = ordered.last else { return [] }
        let maximum = max(ordered.map(\.value).max() ?? 1, 1)
        let minimum = min(ordered.map(\.value).min() ?? 0, maximum)
        let valueRange = max(maximum - minimum, maximum * 0.08, 1)
        let timeRange = max(last.timestamp.timeIntervalSince(first.timestamp), 1)
        let inset: CGFloat = 3

        return ordered.map { point in
            let xRatio = point.timestamp.timeIntervalSince(first.timestamp) / timeRange
            let yRatio = (point.value - minimum) / valueRange
            return CGPoint(
                x: inset + (size.width - inset * 2) * xRatio,
                y: inset + (size.height - inset * 2) * (1 - yRatio)
            )
        }
    }
}

private struct UsageSectionLabel: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            Text(index)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(LittleWatchTheme.signal)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(LittleWatchTheme.primaryText)
            Text("/  \(detail)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(LittleWatchTheme.secondaryText)
        }
    }
}

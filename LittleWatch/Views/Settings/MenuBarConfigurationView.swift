import AppKit
import SwiftUI

struct MenuBarConfigurationView: View {
    @ObservedObject var store: AppStore
    @StateObject private var launchAtLoginController = LaunchAtLoginController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                MenuBarPreview(title: store.menuBarTitle)
                displayFields
                formatting
                launchBehavior
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .onAppear {
            launchAtLoginController.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLoginController.refreshStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("顶部栏编排")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text("留下真正需要抬头看见的信息。修改会立即生效。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }

            Spacer()

            Button("恢复默认") {
                withAnimation(.snappy(duration: 0.25)) {
                    store.resetConfiguration()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(LittleWatchTheme.secondaryText)
        }
    }

    private var displayFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "01", title: "显示内容", detail: "启用与排序")

            VStack(spacing: 0) {
                ForEach(Array(store.configuration.fields.enumerated()), id: \.element.id) { index, field in
                    DisplayFieldRow(
                        field: field,
                        sample: sample(for: field.kind),
                        color: color(for: field.kind),
                        canMoveUp: store.canMove(field.kind, direction: -1),
                        canMoveDown: store.canMove(field.kind, direction: 1),
                        onEnabledChange: { store.setEnabled($0, for: field.kind) },
                        onLabelChange: { store.setLabel($0, for: field.kind) },
                        onMoveUp: {
                            withAnimation(.snappy(duration: 0.22)) {
                                store.moveField(field.kind, direction: -1)
                            }
                        },
                        onMoveDown: {
                            withAnimation(.snappy(duration: 0.22)) {
                                store.moveField(field.kind, direction: 1)
                            }
                        }
                    )

                    if index < store.configuration.fields.count - 1 {
                        Divider()
                            .overlay(LittleWatchTheme.hairline)
                            .padding(.leading, 66)
                    }
                }
            }
            .instrumentCard()
        }
    }

    private var formatting: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "02", title: "显示格式", detail: "密度与可读性")

            VStack(spacing: 0) {
                SettingControlRow(
                    title: "显示模式",
                    detail: "固定显示全部，或按顺序逐项轮换",
                    symbol: "rectangle.3.group"
                ) {
                    Picker("", selection: binding(\.displayMode)) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                if store.configuration.displayMode == .rotating {
                    controlDivider

                    SettingControlRow(
                        title: "轮换周期",
                        detail: "每隔多久切换到下一项",
                        symbol: "timer"
                    ) {
                        Picker("", selection: binding(\.rotationIntervalSeconds)) {
                            ForEach([5, 10, 15], id: \.self) { seconds in
                                Text("\(seconds) 秒").tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 105)
                    }
                }

                controlDivider

                SettingControlRow(
                    title: "显示字段名称",
                    detail: "例如“消费 $12.84”",
                    symbol: "textformat"
                ) {
                    Toggle("", isOn: binding(\.showLabels))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                controlDivider

                SettingControlRow(
                    title: "紧凑 Token",
                    detail: "184,240 显示为 184K",
                    symbol: "arrow.down.right.and.arrow.up.left"
                ) {
                    Toggle("", isOn: binding(\.compactTokens))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                controlDivider

                SettingControlRow(
                    title: "字段分隔",
                    detail: "控制顶部栏的阅读节奏",
                    symbol: "ellipsis"
                ) {
                    Picker("", selection: binding(\.separator)) {
                        ForEach(SeparatorStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 105)
                }

                controlDivider

                SettingControlRow(
                    title: "金额小数位",
                    detail: "最多保留三位",
                    symbol: "decimalpoint"
                ) {
                    Picker("", selection: binding(\.costPrecision)) {
                        ForEach(0...3, id: \.self) { precision in
                            Text("\(precision) 位").tag(precision)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 105)
                }
            }
            .instrumentCard()
        }
    }

    private var launchBehavior: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "03", title: "启动行为", detail: "macOS 登录项")

            SettingControlRow(
                title: "登录时自动启动",
                detail: launchAtLoginController.statusDetail,
                symbol: "power"
            ) {
                HStack(spacing: 10) {
                    if launchAtLoginController.requiresApproval {
                        Button("打开系统设置") {
                            launchAtLoginController.openSystemSettings()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.signal)
                    }

                    if launchAtLoginController.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { launchAtLoginController.isEnabled },
                            set: { launchAtLoginController.setEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(launchAtLoginController.isUpdating)
                }
            }
            .instrumentCard()
        }
    }

    private var controlDivider: some View {
        Divider()
            .overlay(LittleWatchTheme.hairline)
            .padding(.leading, 54)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { store.configuration[keyPath: keyPath] },
            set: { store.configuration[keyPath: keyPath] = $0 }
        )
    }

    private func sample(for kind: MetricKind) -> String {
        switch kind {
        case .cost:
            MenuBarFormatter().formatCost(
                store.snapshot.costUSD,
                precision: store.configuration.costPrecision
            )
        case .tokens:
            MenuBarFormatter().formatTokens(
                store.snapshot.tokenCount,
                compact: store.configuration.compactTokens
            )
        case .cpu:
            MenuBarFormatter().formatPercent(store.systemSnapshot.cpuUsagePercent, prefix: "CPU")
        case .memory:
            MenuBarFormatter().formatPercent(store.systemSnapshot.memoryUsagePercent, prefix: "MEM")
        case .diskUsage:
            MenuBarFormatter().formatPercent(store.systemSnapshot.diskUsagePercent, prefix: "DISK")
        case .diskFree:
            MenuBarFormatter().formatDiskFree(store.systemSnapshot.diskFreeBytes)
        }
    }

    private func color(for kind: MetricKind) -> Color {
        switch kind {
        case .cost: LittleWatchTheme.amber
        case .tokens: LittleWatchTheme.cyan
        case .cpu: LittleWatchTheme.signal
        case .memory: Color(red: 0.68, green: 0.55, blue: 1.0)
        case .diskUsage: Color(red: 1.0, green: 0.48, blue: 0.40)
        case .diskFree: Color(red: 0.38, green: 0.78, blue: 1.0)
        }
    }
}

private struct MenuBarPreview: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LIVE PREVIEW")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(LittleWatchTheme.signal)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(LittleWatchTheme.signal)
                        .frame(width: 5, height: 5)
                    Text("SYNCED")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(LittleWatchTheme.secondaryText)
                }
            }

            HStack(spacing: 0) {
                HStack(spacing: 15) {
                    Image(systemName: "apple.logo")
                    Text("Little Watch")
                        .fontWeight(.semibold)
                    Text("文件")
                    Text("编辑")
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    Text(title)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.black.opacity(0.88))

                Text(Date(), style: .time)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.82))
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 14)
            .frame(height: 31)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), Color(red: 0.83, green: 0.84, blue: 0.83)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.25))
                GridTexture()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LittleWatchTheme.signal.opacity(0.20), lineWidth: 1)
        }
    }
}

private struct GridTexture: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0.0, through: size.width, by: 24).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0.0, through: size.height, by: 24).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color.white.opacity(0.025)), lineWidth: 0.5)
        }
    }
}

private struct DisplayFieldRow: View {
    let field: DisplayFieldConfiguration
    let sample: String
    let color: Color
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEnabledChange: (Bool) -> Void
    let onLabelChange: (String) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.13))
                Image(systemName: field.kind.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                TextField(
                    "字段名称",
                    text: Binding(get: { field.label }, set: { onLabelChange($0) })
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                    .frame(maxWidth: 150)

                Text(sample)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(color.opacity(field.isEnabled ? 0.92 : 0.38))
            }

            Spacer()

            HStack(spacing: 3) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .help("向前移动")

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .help("向后移动")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(LittleWatchTheme.secondaryText)

            Toggle(
                "",
                isOn: Binding(get: { field.isEnabled }, set: { onEnabledChange($0) })
            )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 66)
        .opacity(field.isEnabled ? 1 : 0.58)
    }
}

private struct SettingControlRow<Control: View>: View {
    let title: String
    let detail: String
    let symbol: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LittleWatchTheme.secondaryText)
                .frame(width: 25)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }

            Spacer()
            control
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 58)
    }
}

private struct SectionLabel: View {
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

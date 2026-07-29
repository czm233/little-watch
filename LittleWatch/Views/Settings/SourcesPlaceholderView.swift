import SwiftUI

struct SourcesPlaceholderView: View {
    @ObservedObject var store: AppStore
    @State private var baseURLString = ""
    @State private var password = ""
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case baseURL
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statusCard
                localSourceCard
                configurationCard
                endpointGuide
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .onAppear {
            baseURLString = store.sourceConfiguration.baseURLString
        }
    }

    private var localSourceCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LittleWatchTheme.cyan.opacity(0.13))
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(LittleWatchTheme.cyan)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("本机状态")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.primaryText)
                    Text("无需配置")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(LittleWatchTheme.signal)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(LittleWatchTheme.signal.opacity(0.10)))
                }
                Text("直接从 macOS 读取，每 5 秒更新；不依赖网络。")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }

            Spacer()

            SourceFact(label: "CPU", value: localPercent(store.systemSnapshot.cpuUsagePercent), color: LittleWatchTheme.signal)
            SourceFact(label: "MEM", value: localPercent(store.systemSnapshot.memoryUsagePercent), color: LittleWatchTheme.cyan)
            SourceFact(label: "FREE", value: localDiskFree, color: LittleWatchTheme.primaryText)
        }
        .padding(20)
        .instrumentCard()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("数据来源")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(LittleWatchTheme.primaryText)
            Text("来源负责取得数据；显示模块只决定如何呈现。")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(LittleWatchTheme.secondaryText)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(statusColor.opacity(0.13))
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(store.sourceName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(LittleWatchTheme.primaryText)
                        Text(store.connectionStatusText.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(statusColor.opacity(0.10)))
                    }
                    Text(store.connectionStatusDetail)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            isFailure
                                ? Color.red.opacity(0.82)
                                : LittleWatchTheme.secondaryText
                        )
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(
                        store.refreshState == .refreshing ? "刷新中" : "立即刷新",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(minWidth: 70)
                }
                .disabled(
                    !store.hasConfiguredSource
                        || !store.hasStoredCredential
                        || store.refreshState == .refreshing
                )
            }

            Divider().overlay(LittleWatchTheme.hairline)

            HStack(spacing: 34) {
                SourceFact(
                    label: "TODAY COST",
                    value: MenuBarFormatter().formatCost(
                        store.snapshot.costUSD,
                        precision: store.configuration.costPrecision
                    ),
                    color: LittleWatchTheme.amber
                )
                SourceFact(
                    label: "TODAY TOKENS",
                    value: MenuBarFormatter().formatTokens(
                        store.snapshot.tokenCount,
                        compact: true
                    ),
                    color: LittleWatchTheme.cyan
                )
                SourceFact(
                    label: "LIVE TPM",
                    value: rateText(store.snapshot.tokensPerMinute),
                    color: LittleWatchTheme.signal
                )
                SourceFact(
                    label: "POLLING",
                    value: "\(store.sourceConfiguration.pollingIntervalSeconds)s",
                    color: LittleWatchTheme.primaryText
                )
            }
        }
        .padding(20)
        .instrumentCard()
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接配置")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.primaryText)
                    Text("密码只写入 macOS Keychain")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "key.horizontal.fill")
                    .foregroundStyle(LittleWatchTheme.signal)
            }
            .padding(18)

            Divider().overlay(LittleWatchTheme.hairline)

            inputRow(
                title: "服务地址",
                detail: "CPA Usage Keeper 根地址",
                symbol: "network"
            ) {
                TextField("http://host:port", text: $baseURLString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .baseURL)
                    .frame(maxWidth: 310)
            }

            Divider().overlay(LittleWatchTheme.hairline).padding(.leading, 58)

            inputRow(
                title: "登录密码",
                detail: store.hasStoredCredential ? "已保存；留空继续使用现有密码" : "尚未保存凭证",
                symbol: "lock.fill"
            ) {
                SecureField(store.hasStoredCredential ? "" : "输入登录密码", text: $password)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .password)
                    .frame(maxWidth: 310)
                    .overlay(alignment: .trailing) {
                        if store.hasStoredCredential, password.isEmpty {
                            Text("••••••••")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(LittleWatchTheme.primaryText)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            }

            if usesPlainHTTP {
                Divider().overlay(LittleWatchTheme.hairline).padding(.leading, 58)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(LittleWatchTheme.amber)
                    Text("当前地址使用 HTTP，密码和会话会在网络中明文传输。功能可以运行，但建议尽快为服务配置 HTTPS。")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LittleWatchTheme.secondaryText)
                        .lineSpacing(3)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(LittleWatchTheme.amber.opacity(0.045))
            }

            Divider().overlay(LittleWatchTheme.hairline)

            HStack {
                if store.hasStoredCredential {
                    Button("清除凭证") {
                        password = ""
                        store.clearSourceCredential()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.red.opacity(0.72))
                }

                Spacer()

                Button {
                    focusedField = nil
                    Task {
                        isSaving = true
                        let succeeded = await store.configureSource(
                            baseURLString: baseURLString,
                            password: password
                        )
                        if succeeded { password = "" }
                        isSaving = false
                    }
                } label: {
                    Label(
                        isSaving ? "正在连接" : "连接并保存",
                        systemImage: isSaving ? "hourglass" : "bolt.horizontal.circle.fill"
                    )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.sidebar.opacity(canSubmit ? 1 : 0.48))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LittleWatchTheme.signal.opacity(canSubmit ? 1 : 0.22))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(16)
        }
        .instrumentCard()
    }

    private var endpointGuide: some View {
        HStack(alignment: .top, spacing: 18) {
            EndpointRole(
                index: "01",
                title: "登录",
                detail: "创建内存会话 Cookie"
            )
            EndpointRole(
                index: "02",
                title: "今日总览",
                detail: "累计金额与 Token"
            )
            EndpointRole(
                index: "03",
                title: "60 分钟实时",
                detail: "TPM/RPM 活跃速度"
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LittleWatchTheme.hairline, lineWidth: 1)
                }
        )
    }

    private func inputRow<Control: View>(
        title: String,
        detail: String,
        symbol: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LittleWatchTheme.secondaryText)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
    }

    private var usesPlainHTTP: Bool {
        URLComponents(string: baseURLString)?.scheme?.lowercased() == "http"
    }

    private var canSubmit: Bool {
        !isSaving && !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusColor: Color {
        switch store.sourceConnectionState {
        case .connected: LittleWatchTheme.signal
        case .connecting: LittleWatchTheme.cyan
        case .reconnecting: LittleWatchTheme.amber
        case .needsCredential: LittleWatchTheme.amber
        case .failed: Color.red.opacity(0.85)
        }
    }

    private var isFailure: Bool {
        if case .failed = store.sourceConnectionState { return true }
        return false
    }

    private func rateText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func localPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private var localDiskFree: String {
        MenuBarFormatter()
            .formatDiskFree(store.systemSnapshot.diskFreeBytes)
            .replacingOccurrences(of: "FREE ", with: "")
    }
}

private struct SourceFact: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(LittleWatchTheme.secondaryText)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

private struct EndpointRole: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(index)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(LittleWatchTheme.signal)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.primaryText)
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(LittleWatchTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

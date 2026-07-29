# Little Watch

Little Watch 是一个只驻留在 macOS 顶部栏的轻量信息工具，通过可扩展来源读取数据，再由显示模块编排顶部栏内容。

## 当前能力

- 顶部栏实时显示金额与 Token 用量
- 点击顶部栏查看紧凑详情面板
- 独立设置窗口与顶部栏实时预览
- 启用、隐藏和调整显示字段顺序
- 配置字段名称、分隔符、金额精度与 Token 紧凑格式
- 配置自动保存到 `UserDefaults`
- 通过统一 `MetricSource` 协议隔离数据来源
- 首个真实来源：CPA Usage Keeper
- 密码保存在 Little Watch 本机配置，会话 Cookie 只保存在内存
- 每 5 秒刷新今日总览与最近 60 分钟实时窗口
- 原生读取 CPU、内存与磁盘状态
- 固定组合或逐项轮换顶部栏指标

## 技术栈

- Swift 6
- SwiftUI
- AppKit（退出与原生应用能力）
- macOS 14+

## 运行

用 Xcode 打开 `LittleWatch.xcodeproj`，选择 `LittleWatch` scheme 后运行。

也可以在终端执行：

```bash
xcodebuild -project LittleWatch.xcodeproj -scheme LittleWatch -configuration Debug build
```

应用采用 `LSUIElement` 模式，不显示 Dock 图标。运行后请在 macOS 顶部栏寻找用量文本。

## 下载

稳定版本可从 [GitHub Releases](https://github.com/czm233/little-watch/releases) 下载：

1. 下载 `LittleWatch-版本号-macOS-universal.dmg`。
2. 打开 DMG，将 `LittleWatch.app` 拖到其中的 `Applications` 快捷方式。
3. 当前公开包使用临时签名，尚未经过 Apple 公证。首次启动如果被 macOS 拦截，请在 Finder 中右键应用并选择“打开”，然后再次确认。

安装包同时支持 Apple Silicon 和 Intel Mac。每个 DMG 都附带同名 `.sha256` 文件，可用于校验下载完整性。

## 自动构建与发布

- 推送到 `main`：自动运行测试并生成保留 14 天的通用 DMG 构建。
- 推送 `vX.Y.Z` 标签：自动测试、打包 DMG，并创建公开的 GitHub Release。

正式对外分发前仍建议配置 Developer ID 签名与 Apple 公证，以消除 Gatekeeper 警告。

## 结构

```text
LittleWatch/
├── App/          应用入口
├── Models/       配置与标准化指标
├── Services/     配置持久化与顶部栏格式化
├── Sources/      数据来源协议和 CPA Usage Keeper 来源
├── Store/        应用状态
└── Views/        顶部栏面板与设置窗口
```

## CPA Usage Keeper

打开“数据来源”，填写服务根地址和登录密码，然后点击“连接并保存”。

- `overview?range=today` 提供今日累计金额与 Token，是顶部栏的主数据。
- `overview/realtime?window=60m` 提供最近 60 分钟的 TPM/RPM 等实时活跃度。
- 登录失效后会自动重新登录一次。
- 密码保存在当前 macOS 用户的 Little Watch `UserDefaults` 中，不访问 macOS Keychain，也不会进入代码仓库。该本地配置未加密，请只在受信任的 Mac 账户中使用。

应用不内置默认服务地址。为兼容现有来源，应用允许用户配置 HTTP 地址；生产使用时应为服务配置 HTTPS，避免密码和会话在网络中明文传输。

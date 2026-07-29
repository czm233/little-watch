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
- 密码保存在 macOS Keychain，会话 Cookie 只保存在内存
- 每 5 秒刷新今日总览与最近 60 分钟实时窗口

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
- 密码和 Token 等敏感信息不会进入代码仓库或普通配置文件。

当前默认服务地址使用 HTTP。为兼容该服务，应用允许明文 HTTP 请求；生产使用时应为服务配置 HTTPS，避免密码和会话在网络中明文传输。

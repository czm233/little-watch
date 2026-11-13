# Little Watch 项目规约

## 改代码后的交付流程（2026-11-13 用户指定，必须执行）

任何代码改动（修 bug、加功能、改 UI）完成后，必须依次做完以下三步，不得只改代码就交付：

1. **关闭当前已启动的旧版 app**：`osascript -e 'tell application "LittleWatch" to quit'`，不响应时 `pkill -x LittleWatch`
2. **编译并安装新版**：Release 构建 → 替换 `/Applications/LittleWatch.app` → 清 quarantine → `open` 启动 → `pgrep -x LittleWatch` 确认进程存活
3. **明确提醒用户去看新版本**

约定：
- 构建用 `-derivedDataPath /tmp/lw-dd`；版本号递增（当前 0.3.9），`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`
- 每次改动单独 commit；**push 仍需用户批准；"submit"/"提交"同样不等于 push 授权**（2026-11-13 事故：用户说 submit，AI 在已全部 commit 的情况下自行推送到 GitHub）——提交类指令在已全部 commit 时视为无操作或反向确认，只有用户明说"推送/push 到 GitHub"才推
- 推送前按用户级规则 18.7 全量扫描待推送提交（密钥/URL/凭证文件）
- 安装前 `xattr -dr com.apple.quarantine`，安装后确认 `pgrep` 存活才算交付完成
- app 必须保持正式开发者签名（Team `9F2BHVCLNL`）；麦克风等 TCC 敏感权限依赖签名 + entitlements（见 `LittleWatch/Resources/LittleWatch.entitlements`），Ad-hoc 签名会被系统静默拒绝弹窗

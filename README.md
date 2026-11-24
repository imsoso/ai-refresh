# ai-refresh

定时用一次**最小请求**唤醒 AI 编程订阅（GLM Coding Plan 等），提前开启 5 小时用量窗口，并让休眠中的 Mac 按时醒来执行。

## 为什么需要

- 多数 AI Coding 订阅按 **5 小时滚动窗口**计量：窗口从你第一次请求开始算。在固定时间发一个极小请求，等于把窗口"预约定"在你想要的时间段。
- MacBook 合盖睡眠时 cron 不会跑。本工具用 `pmset schedule wake` 预约唤醒事件，让 cron 能准时执行。
- 唤醒事件采用**滚动预约**：每次运行自动补签 30 天后的槽位，无需续期；`ai-toggle off` 一键全部取消。

## 组成

| 脚本 | 作用 |
|---|---|
| `refresh-ai.sh` | 向订阅 CLI 发送最小请求（回复一个词、禁用一切工具），附带重试/代理降级/并发锁 |
| `ai-refresh-toggle.sh` | `on` 预约未来 30 天的唤醒 + 写入 crontab；`off` 只取消唤醒（crontab 保留）；`status` 查看状态 |
| `schedule-wakes.sh` | 批量预约未来 N 天每天 07:59 / 12:59 / 17:59 的 pmset 唤醒（幂等） |

默认节奏：crontab 每天 **08:00 / 13:00 / 18:00** 跑 `refresh-ai.sh`，pmset 提前 1 分钟唤醒。

## 支持的 CLI

当前内置（按优先级）：

1. **zcode** — `zcode -p`（GLM Coding Plan），默认模型 GLM-5.3-Flash 低推理档
2. **opencode** — `opencode run -m zhipuai-coding-plan/glm-5.3-flash`（zcode 不在时的回落）

### zcode 无头模式的一次性配置

zcode 的凭证默认放在 macOS 钥匙串，无头 cron 进程读不到，会报 "System credential storage is unavailable"。改用独立密钥文件 + 独立凭证存储（与桌面端互不影响）：

```bash
# 1. 生成 CLI 专用加密密钥（32–4096 字节，权限必须 600）
dd if=/dev/urandom of=~/.zcode/cli/credential-secret bs=64 count=1
chmod 600 ~/.zcode/cli/credential-secret

# 2. 一次性登录（--no-browser 打印 URL，浏览器授权后自动写入）
export ZCODE_CREDENTIAL_SECRET_FILE=~/.zcode/cli/credential-secret
export ZCODE_CREDENTIALS_FILE=~/.zcode/cli/credentials.json
zcode login bigmodel --no-browser
```

登录会把默认模型写进 `~/.zcode/v2/provider_config.json` 的 `config.defaultModelSelection`，之后 `zcode -p "..."` 无头可用。想用低档位省 token，把该字段改成：

```json
"defaultModelSelection": {
  "providerId": "account:bigmodel-individual-coding-plan",
  "modelId": "GLM-5.3-Flash",
  "options": { "reasoningLevel": "low" }
}
```

`refresh-ai.sh` 会自动带上这两个环境变量调用 zcode。

### 添加其他 CLI

在 `refresh-ai.sh` 里照抄一个 `refresh_xxx()` 函数并挂进 case 分支即可，函数只需一次最小调用（claude：`--print`；codex：`codex exec --skip-git-repo-check`）。

## 安装

```bash
cp refresh-ai.sh ai-refresh-toggle.sh schedule-wakes.sh ~/bin/
chmod +x ~/bin/refresh-ai.sh ~/bin/ai-refresh-toggle.sh ~/bin/schedule-wakes.sh
ln -sf ai-refresh-toggle.sh ~/bin/ai-toggle   # 可选短命令
```

pmset 免密预约（只需一次）：

```bash
sudo bash -c 'echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/pmset" > /etc/sudoers.d/pmset'
```

启用：

```bash
~/bin/ai-toggle on      # 写 crontab + 预约 30 天唤醒
~/bin/ai-toggle status  # 查看状态
~/bin/refresh-ai.sh     # 手动刷新一次（跑当前默认 CLI）
~/bin/refresh-ai.sh zcode
~/bin/refresh-ai.sh opencode
```

## 依赖

- macOS + 至少一个已登录的 AI CLI
- Node（zcode 回路需要；opencode 不需要）
- 无 GNU 依赖：超时控制用系统自带 perl 实现
- `defaultModelSelection` 里的 `providerId` 取决于你的登录渠道：bigmodel 账号是 `account:bigmodel-individual-coding-plan`，Z.ai 账号是 `account:zai-individual-coding-plan`，以 `zcode login` 后自动写入的值为准
- ZCode CLI 路径可用环境变量 `ZCODE_CJS` 覆盖（默认 `/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs`，官方 dmg 安装即此路径）

## License

MIT

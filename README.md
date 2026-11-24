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

1. **zcode** — ZCode.app 自带的 CLI（`/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs`，走 GLM Coding Plan）
2. **opencode** — `opencode run -m zhipuai-coding-plan/glm-4.5-air`（zcode 不在时的回落）

添加其他 CLI（claude / codex 等）：在 `refresh-ai.sh` 里照抄一个 `refresh_xxx()` 函数并挂进 case 分支即可，函数只需一次 `--print` 式的最小调用。

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

## License

MIT

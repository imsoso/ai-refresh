# ai-refresh

[中文](#中文) | [English](#english)

定时用一次**最小请求**唤醒 AI 编程订阅（GLM Coding Plan 等），提前开启 5 小时用量窗口；同时让休眠中的 Mac 按时醒来执行。适用于 zcode / opencode / claude / codex 等 CLI 订阅。

---

<a id="中文"></a>

## 它解决什么问题

1. 多数 AI Coding 订阅按 **5 小时滚动窗口**计量，窗口从你第一次请求开始算。在固定时间发一个极小请求（回复一个词、禁用一切工具），等于把窗口"预约"到你想要的时间段——代价几乎为零。
2. MacBook 合盖睡眠时 **cron 不会执行**。本工具用 `pmset schedule wake` 预约唤醒事件，让 cron 每天准时跑；唤醒采用**滚动预约**，每次运行自动补签 30 天后的槽位，永不中断。

## 组成

| 脚本 | 作用 |
|---|---|
| `refresh-ai.sh` | 主脚本：向订阅 CLI 发送最小请求，带重试 / 代理降级 / 并发锁 |
| `ai-refresh-toggle.sh` | `on` 写 crontab + 预约未来 30 天唤醒；`off` 只取消唤醒（crontab 保留）；`status` 查看状态 |
| `schedule-wakes.sh` | 批量预约未来 N 天每天 07:59 / 12:59 / 17:59 的 pmset 唤醒（幂等） |

默认节奏：crontab 每天 **08:00 / 13:00 / 18:00** 触发，pmset 提前 1 分钟唤醒。日志在 `~/.ai-refresh.log`。

## 快速开始（怎么做）

> 前提：macOS；至少装一个受支持的 AI CLI（见[支持的 CLI](#支持的-cli)）。

### 第 1 步：安装脚本

```bash
git clone https://github.com/imsoso/ai-refresh.git
cp ai-refresh/refresh-ai.sh ai-refresh/ai-refresh-toggle.sh ai-refresh/schedule-wakes.sh ~/bin/
chmod +x ~/bin/refresh-ai.sh ~/bin/ai-refresh-toggle.sh ~/bin/schedule-wakes.sh
ln -sf ai-refresh-toggle.sh ~/bin/ai-toggle   # 可选短命令
```

如果 `~/bin` 不在 PATH，往 `~/.zshrc` 加一行：`export PATH="$HOME/bin:$PATH"`

### 第 2 步：zcode 一次性配置（用 zcode 才需要）

zcode 的凭证默认放在 macOS 钥匙串，cron 这类无头进程读不到，会报 `System credential storage is unavailable`。改用独立密钥文件 + 独立凭证存储（与桌面端互不影响）：

```bash
# 2.1 生成 CLI 专用加密密钥（必须 32–4096 字节，权限必须 600）
dd if=/dev/urandom of=~/.zcode/cli/credential-secret bs=64 count=1
chmod 600 ~/.zcode/cli/credential-secret

# 2.2 一次性登录（--no-browser 打印授权 URL，浏览器打开并登录后自动写入）
export ZCODE_CREDENTIAL_SECRET_FILE=~/.zcode/cli/credential-secret
export ZCODE_CREDENTIALS_FILE=~/.zcode/cli/credentials.json
zcode login bigmodel --no-browser      # Z.ai 账号则用: zcode login zai --no-browser

# 2.3 验证无头可用（应输出 ready）
zcode -p "Reply only with: ready"
```

登录会自动把默认模型写进 `~/.zcode/v2/provider_config.json` 的 `config.defaultModelSelection`。想用低推理档省 token，把它改成：

```json
"defaultModelSelection": {
  "providerId": "account:bigmodel-individual-coding-plan",
  "modelId": "GLM-5.3-Flash",
  "options": { "reasoningLevel": "low" }
}
```

> `providerId` 取决于你的登录渠道：bigmodel 账号是 `account:bigmodel-individual-coding-plan`，Z.ai 账号是 `account:zai-individual-coding-plan`，以 `zcode login` 后自动写入的值为准。
> ZCode CLI 路径可用环境变量 `ZCODE_CJS` 覆盖（默认 `/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs`，官方 dmg 安装即此路径）。

`refresh-ai.sh` 调用 zcode 时会自动带上这两个环境变量，日常无需手动 export。

### 第 3 步：pmset 免密（合盖唤醒才需要）

预约唤醒需要 sudo 免密，只需配置一次：

```bash
sudo bash -c 'echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/pmset" > /etc/sudoers.d/pmset'
```

### 第 4 步：开启

```bash
~/bin/ai-toggle on       # 写 crontab + 预约 30 天唤醒
~/bin/ai-toggle status   # 查看状态
```

### 第 5 步：验证

```bash
~/bin/refresh-ai.sh            # 手动刷新一次（当前主 CLI）
tail ~/.ai-refresh.log         # cron 触发后的日志也在这里
pmset -g sched | head -5       # 确认唤醒事件已预约
```

看到 `ZCode ✓` / `OpenCode ✓` 即为触发成功——从这一刻起，订阅的 5h 窗口已经开启。

## 日常使用

```bash
~/bin/ai-toggle on              # 开：crontab + 30 天唤醒
~/bin/ai-toggle off             # 关：只取消唤醒（crontab 保留，Mac 醒着时照常刷新）
~/bin/ai-toggle status          # 状态：crontab / 唤醒队列 / 下次唤醒
~/bin/ai-toggle list            # 各 AI 开关与 CLI 安装情况

~/bin/ai-toggle enable claude   # 启用某个 AI（zcode|opencode|claude|codex）
~/bin/ai-toggle disable codex   # 停用某个 AI

~/bin/refresh-ai.sh             # 跑所有开关打开的 AI
~/bin/refresh-ai.sh codex       # 手动刷单个（无论开关状态）
```

## 支持的 CLI

| AI | 命令 | 默认 |
|---|---|---|
| zcode | `zcode -p`（GLM Coding Plan，GLM-5.3-Flash 低推理档） | **开** |
| opencode | `opencode run -m zhipuai-coding-plan/glm-5.3-flash` | 关 |
| claude | `claude --model haiku --print`（`npm i -g @anthropic-ai/claude-code`） | 关 |
| codex | `codex exec -m gpt-5.4-mini`（`npm i -g @openai/codex`，配套 `codex-token-refresh.py` 自动续 OAuth token） | 关 |

- 开关状态存于 `~/.config/ai-refresh/enabled`（每行一个名字）；文件不存在时默认只启用 zcode
- 未安装对应 CLI 时，启用状态会以英文提示并附安装命令，不影响其他 AI
- codex 走 openai.com 需要能直连的网络；claude/codex 装好后 `ai-toggle enable` 即生效，无需改脚本

## 依赖

- macOS + 至少一个已登录的 AI CLI
- Node（zcode 回路需要；opencode 不需要）
- 无 GNU 依赖：超时控制用系统自带 perl 实现

## 故障排查

- **`System credential storage is unavailable`**：没做第 2 步，或密钥文件权限不是 600 / 字节数不在 32–4096。
- **`Select a model before sending a message`**：`~/.zcode/v2/provider_config.json` 里没有 `config.defaultModelSelection`——完成登录即可，或手动补上（见第 2 步 JSON）。
- **代理环境**：脚本重试时会自动去掉代理变量再试一次，无需手动处理。
- **只想周末/工作日跑**：直接改 crontab（`crontab -e`），`ai-toggle` 不会覆盖你改过的时间。

## License

MIT

---

<a id="english"></a>

# ai-refresh (English)

Wake up AI coding subscriptions (GLM Coding Plan etc.) with one **minimal request** on a schedule, opening their 5-hour usage window ahead of time — and make a sleeping Mac wake itself up to do it. Works with zcode / opencode / claude / codex CLI subscriptions.

## What problem it solves

1. Most AI coding plans meter usage in a **rolling 5-hour window** that starts at your first request. Firing a tiny request at a fixed time (reply with one word, all tools disabled) "books" the window to start exactly when you want — at almost zero cost.
2. **cron doesn't run while a MacBook is asleep.** This tool schedules `pmset` wake events so cron fires on time. Wake booking is **rolling**: every run re-books the slots 30 days ahead, so it never lapses.

## Components

| Script | Purpose |
|---|---|
| `refresh-ai.sh` | Main runner: fires the minimal request at your CLI, with retries / proxy fallback / a concurrency lock |
| `ai-refresh-toggle.sh` | `on` writes crontab + books 30 days of wakes; `off` cancels wakes only (crontab stays); `status` shows state |
| `schedule-wakes.sh` | Books pmset wakes at 07:59 / 12:59 / 17:59 for the next N days (idempotent) |

Default schedule: crontab fires at **08:00 / 13:00 / 18:00** daily; pmset wakes the Mac 1 minute earlier. Logs: `~/.ai-refresh.log`.

## Quick start (how to set it up)

> Prerequisites: macOS, and at least one supported AI CLI (see [Supported CLIs](#supported-clis)).

### Step 1: Install the scripts

```bash
git clone https://github.com/imsoso/ai-refresh.git
cp ai-refresh/refresh-ai.sh ai-refresh/ai-refresh-toggle.sh ai-refresh/schedule-wakes.sh ~/bin/
chmod +x ~/bin/refresh-ai.sh ~/bin/ai-refresh-toggle.sh ~/bin/schedule-wakes.sh
ln -sf ai-refresh-toggle.sh ~/bin/ai-toggle   # optional short command
```

If `~/bin` is not on your PATH, add to `~/.zshrc`: `export PATH="$HOME/bin:$PATH"`

### Step 2: One-time zcode setup (only needed for zcode)

zcode stores credentials in the macOS Keychain by default, which headless processes like cron cannot read — you'll see `System credential storage is unavailable`. Use a standalone secret file + standalone credential store instead (the desktop app is unaffected):

```bash
# 2.1 Generate a CLI-only encryption key (must be 32–4096 bytes, mode must be 600)
dd if=/dev/urandom of=~/.zcode/cli/credential-secret bs=64 count=1
chmod 600 ~/.zcode/cli/credential-secret

# 2.2 One-time login (--no-browser prints an auth URL; open it in a browser and sign in)
export ZCODE_CREDENTIAL_SECRET_FILE=~/.zcode/cli/credential-secret
export ZCODE_CREDENTIALS_FILE=~/.zcode/cli/credentials.json
zcode login bigmodel --no-browser      # for Z.ai accounts use: zcode login zai --no-browser

# 2.3 Verify headless works (should print ready)
zcode -p "Reply only with: ready"
```

Login writes your default model into `config.defaultModelSelection` in `~/.zcode/v2/provider_config.json`. To save tokens, switch to the low reasoning tier:

```json
"defaultModelSelection": {
  "providerId": "account:bigmodel-individual-coding-plan",
  "modelId": "GLM-5.3-Flash",
  "options": { "reasoningLevel": "low" }
}
```

> `providerId` depends on your login channel: bigmodel accounts use `account:bigmodel-individual-coding-plan`, Z.ai accounts use `account:zai-individual-coding-plan` — trust whatever `zcode login` writes automatically.
> The ZCode CLI path can be overridden with the `ZCODE_CJS` env var (default `/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs`, which is where the official dmg installs it).

`refresh-ai.sh` passes both env vars automatically when calling zcode — no manual export needed day to day.

### Step 3: Passwordless pmset (only needed for wake-from-sleep)

Booking wake events requires passwordless sudo, configured once:

```bash
sudo bash -c 'echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/pmset" > /etc/sudoers.d/pmset'
```

### Step 4: Turn it on

```bash
~/bin/ai-toggle on       # writes crontab + books 30 days of wakes
~/bin/ai-toggle status   # check state
```

### Step 5: Verify

```bash
~/bin/refresh-ai.sh            # one manual refresh (current primary CLI)
tail ~/.ai-refresh.log         # cron-triggered runs log here too
pmset -g sched | head -5       # confirm wake events are booked
```

Seeing `ZCode ✓` / `OpenCode ✓` means the trigger succeeded — your plan's 5h window is open from that moment.

## Daily usage

```bash
~/bin/ai-toggle on              # on: crontab + 30 days of wakes
~/bin/ai-toggle off             # off: cancels wakes only (crontab stays; refreshes still run while awake)
~/bin/ai-toggle status          # state: crontab / wake queue / next wake
~/bin/ai-toggle list            # per-AI switches and CLI availability

~/bin/ai-toggle enable claude   # enable one AI (zcode|opencode|claude|codex)
~/bin/ai-toggle disable codex   # disable one AI

~/bin/refresh-ai.sh             # run every switched-on AI
~/bin/refresh-ai.sh codex       # manually refresh one (ignores the switch)
```

## Supported CLIs

| AI | Command | Default |
|---|---|---|
| zcode | `zcode -p` (GLM Coding Plan, GLM-5.3-Flash low reasoning tier) | **on** |
| opencode | `opencode run -m zhipuai-coding-plan/glm-5.3-flash` | off |
| claude | `claude --model haiku --print` (`npm i -g @anthropic-ai/claude-code`) | off |
| codex | `codex exec -m gpt-5.4-mini` (`npm i -g @openai/codex`, with `codex-token-refresh.py` auto-refreshing the OAuth token) | off |

- Switch state lives in `~/.config/ai-refresh/enabled` (one name per line); when the file is absent, only zcode is enabled
- If a CLI isn't installed, an English message with the install command is printed — other AIs are unaffected
- codex needs direct network access to openai.com; once claude/codex are installed, `ai-toggle enable` is all it takes

## Requirements

- macOS + at least one logged-in AI CLI
- Node (needed for zcode; not for opencode)
- No GNU dependencies: the timeout helper uses the system perl

## Troubleshooting

- **`System credential storage is unavailable`** — Step 2 not done, or the key file isn't mode 600 / not 32–4096 bytes.
- **`Select a model before sending a message`** — no `config.defaultModelSelection` in `~/.zcode/v2/provider_config.json`. Complete the login, or add it manually (see the JSON in Step 2).
- **Proxy environments** — on retry the script automatically strips proxy variables and tries again; no manual action needed.
- **Weekends / weekdays only** — edit the crontab directly (`crontab -e`); `ai-toggle` won't overwrite your modified times.

## License

MIT


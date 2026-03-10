# PRECC — Predictive Error Correction for Claude Code

PRECC saves **~34% of Claude Code costs** by fixing bash commands before they fail and compressing tool output.

## Install

### Option 1: Pre-built binary (recommended)

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/yijunyu/precc-cc/main/scripts/install.sh | bash
```

**Windows (PowerShell):**

```powershell
iwr -useb https://raw.githubusercontent.com/yijunyu/precc-cc/main/scripts/install.ps1 | iex
```

Then run:

```bash
precc init
```

### Option 2: Claude Code Plugin

```bash
claude plugin marketplace add yijunyu/precc
claude plugin install precc
```

Restart Claude Code to activate the plugin.

## Usage

Once installed, PRECC works automatically. Every bash command Claude Code runs passes through the hook, which silently fixes common mistakes and compresses output.

```bash
# Initialize databases and mine existing session history
precc init
precc ingest --all

# Re-mine all sessions from scratch (e.g. after a mining logic update)
precc ingest --all --force

# View what PRECC has learned
precc skills list
precc skills show <name>    # full trigger/action detail
precc skills export <name>  # dump as TOML (for sharing/backup)
precc skills edit <name>    # open in $EDITOR and reimport on save

# View savings report
precc report
```

## What It Does

- **Fixes wrong-directory commands** — Detects when `cargo build` or `npm test` is run in the wrong directory and prepends `cd /correct/path &&`
- **Prevents repeated failures** — Learns from past session failures and auto-corrects commands that would fail the same way
- **Compresses CLI output** — Rewrites commands to use [RTK](https://github.com/rtk-ai/rtk) for 60-90% smaller output, reducing context growth
- **Suggests GDB debugging** — When a command fails repeatedly, suggests `precc debug` instead of edit-compile-retry cycles

## Security

As of v0.2.0, all PRECC databases (`heuristics.db`, `history.db`, `metrics.db`) are
**AES-256 encrypted** via SQLCipher. The encryption key is derived automatically from
your machine ID and username using HKDF-SHA256 — no passphrase required, no key stored
on disk. The databases are unreadable on any other machine.

```
$ precc init
  Encryption: AES-256 (machine-bound key, first 4 bytes: a3f7...)
```

## Requirements

- Claude Code (with hooks support)
- [RTK](https://github.com/rtk-ai/rtk) (optional, for output compression)

## Measured Results

Analyzed across 29 real Claude Code sessions, 5 projects, 5,384 bash calls, $878 total spend:

| Metric | Value |
|--------|-------|
| **Cost savings** | **$296 / $878 (34%)** |
| **Failures prevented** | **352 / 358 (98%)** |
| **Bash calls improved** | **894 / 5,384 (17%)** |
| **Cache reads saved** | **988M / 1.67B tokens (59%)** |
| **Hook latency** | **2.93ms avg (1.77ms overhead)** |

---
name: precc
description: Predictive Error Correction for Claude Code — corrects bash commands before execution
version: 1.0.0
emoji: "🔧"
homepage: https://github.com/yijunyu/precc-cc
os:
  - linux
  - macos
metadata:
  openclaw:
    requires:
      bins:
        - precc
        - precc-hook
      config:
        - ~/.local/share/precc/history.db
        - ~/.local/share/precc/heuristics.db
        - ~/.claude/settings.json
      env:
        - PRECC_LICENSE_KEY
    primaryEnv: PRECC_LICENSE_KEY
env:
  - name: PRECC_LICENSE_KEY
    required: false
    description: Optional Pro license key for premium features (savings --all)
dependencies:
  - name: precc
    type: binary
    url: https://github.com/yijunyu/precc-cc/releases
  - name: cocoindex-code
    type: pip
    required: false
    url: https://pypi.org/project/cocoindex-code/
author: yijunyu
links:
  homepage: https://github.com/yijunyu/precc-cc
  repository: https://github.com/yijunyu/precc-cc
---

# PRECC — Predictive Error Correction for Claude Code

PRECC saves **~34% of Claude Code costs** through three pillars: correcting bash commands before they fail, compressing tool output, and reducing context token usage via semantic search and file compression. Ships as a single Rust binary.

## Three Savings Pillars

### Pillar 1: Command Correction & Output Compression
- **Fixes wrong-directory commands** — Detects when `cargo build` or `npm test` is run in the wrong directory and prepends `cd /correct/path &&`
- **Prevents repeated failures** — Learns from past session failures and auto-corrects commands that would fail the same way
- **Compresses CLI output** — Rewrites verbose commands for 60-90% smaller output via RTK
- **Suggests GDB debugging** — When a command fails repeatedly, suggests `precc debug`

### Pillar 2: Semantic Code Search (cocoindex-code)
- Optional AST-aware semantic search across 28+ languages, saving ~70% of search tokens
- Built into the `precc-hook` binary; no extra scripts needed
- Requires separate `cocoindex-code` install (`pipx install cocoindex-code`)

### Pillar 3: Context File Compression
- Strips filler words from CLAUDE.md and memory files via `precc compress`
- Reduces tokens loaded on every API call (~30% compression)
- Backups saved automatically, revertible with `precc compress --revert`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/yijunyu/precc-cc/main/scripts/install.sh | bash
precc init
```

The install script downloads a platform-specific binary from GitHub Releases, verifies its SHA256 checksum, and places it in `~/.local/bin`. It then configures a PreToolUse hook in `~/.claude/settings.json`.

## Live Status Line

PRECC includes a built-in status line that shows real-time session metrics directly in the Claude Code terminal:

```
PRECC: 12 fixes, ~3.6K tokens saved | 2.1ms avg
```

The status line is automatically configured during installation. It shows:
- **Corrections** — commands fixed in the current session
- **Tokens saved** — estimated token savings from all corrections
- **Hook latency** — average hook execution time

To enable manually, add to `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.local/bin/precc-hook --statusline"
  }
}
```

## What PRECC Modifies

- **`~/.claude/settings.json`** — Adds a `PreToolUse` hook entry pointing to `precc-hook`
- **`~/.local/share/precc/`** — SQLite databases for learned failure-fix patterns and skill heuristics
- **`~/.local/bin/`** — Installs `precc`, `precc-hook`, and `precc-miner` binaries

## Usage

Once installed, PRECC works automatically as a PreToolUse hook.

```bash
# Mine existing session history for failure-fix patterns
precc ingest --all

# View what PRECC has learned
precc skills list

# View unified savings report (all three pillars)
precc savings

# Semantic code search (requires cocoindex-code)
ccc init && ccc index
ccc search "authentication middleware"

# Compress context files
precc compress --dry-run   # preview
precc compress             # compress
precc compress --revert    # revert
```

## Measured Results

| Metric | Value |
|--------|-------|
| **Cost savings** | **$296 / $878 (34%)** |
| **Failures prevented** | **352 / 358 (98%)** |
| **Bash calls improved** | **894 / 5,384 (17%)** |
| **Cache reads saved** | **988M / 1.67B tokens (59%)** |
| **Hook latency** | **2.93ms avg (1.77ms overhead)** |

## Links

- GitHub: https://github.com/yijunyu/precc-cc
- ClawHub: https://clawhub.ai/skills/precc
- cocoindex-code: https://github.com/cocoindex-io/cocoindex-code
- RTK: https://github.com/rtk-ai/rtk

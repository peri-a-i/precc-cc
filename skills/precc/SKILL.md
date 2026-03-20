# PRECC — Predictive Error Correction for Claude Code

PRECC saves **~34% of Claude Code costs** by fixing bash commands before they fail, compressing tool output, and redirecting grep/rg through AST-aware semantic code search.

## What It Does

- **Fixes wrong-directory commands** — Detects when `cargo build` or `npm test` is run in the wrong directory and prepends `cd /correct/path &&`
- **Prevents repeated failures** — Learns from past session failures and auto-corrects commands that would fail the same way
- **Compresses CLI output** — Rewrites commands to use RTK for 60-90% smaller output, reducing context growth
- **AST-driven semantic code search** — Intercepts grep/rg and redirects through cocoindex-code for structure-aware results, saving 70% tokens
- **Suggests GDB debugging** — When a command fails repeatedly, suggests `precc debug` instead of edit-compile-retry cycles

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/yijunyu/precc-cc/main/scripts/install.sh | bash
precc init
```

## Usage

Once installed, PRECC works automatically as a PreToolUse hook. Every bash command Claude Code runs passes through the hook, which silently fixes common mistakes and compresses output.

```bash
# Mine existing session history for failure-fix patterns
precc ingest --all

# View what PRECC has learned
precc skills list

# View savings report (includes RTK + cocoindex-code savings)
precc savings

# Semantic code search (requires cocoindex-code)
ccc init && ccc index
ccc search "authentication middleware"
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
- cocoindex-code: https://github.com/cocoindex-io/cocoindex-code
- RTK: https://github.com/rtk-ai/rtk

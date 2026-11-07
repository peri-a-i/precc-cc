---
name: precc
description: Predictive Error Correction for Claude Code — corrects bash commands before execution, predicts token costs via a trained ML oracle, and captures opt-in counterfactual telemetry
version: 1.1.0
emoji: "🔧"
user-invocable: true
disable-model-invocation: true
homepage: https://github.com/peri-a-i/precc-cc
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
    url: https://github.com/peri-a-i/precc-cc/releases
  - name: cocoindex-code
    type: pip
    required: false
    url: https://pypi.org/project/cocoindex-code/
author: peri-a-i
links:
  homepage: https://github.com/peri-a-i/precc-cc
  repository: https://github.com/peri-a-i/precc-cc
---

# PRECC — Predictive Error Correction for Claude Code

PRECC saves **~34 % of Claude Code costs** through three savings pillars: correcting bash commands before they fail, compressing tool output, and reducing context token usage via semantic search and file compression. v1.1 adds a **token-cost prediction oracle** (`precc predict`) that ships its own trainable ridge model, and **opt-in counterfactual telemetry** for measuring would-have-run vs. did-run deltas. Ships as a single Rust binary.

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
- Reduces tokens loaded on every API call (~30 % compression)
- Backups saved automatically, revertible with `precc compress --revert`

## Token-Cost Prediction Oracle (v1.1)

`precc predict` records a prediction → actual labelled dataset for any
multi-step task you plan in tokens (never in wall-clock time). It ships
two predictors:

- **`heuristic-1`** — rule-based category × length estimator, available
  out of the box.
- **`trained-v1`** — closed-form ridge regression on category +
  log(description length), persisted to
  `~/.local/share/precc/predict_model.json`. Fit it from your own
  closed predictions with `precc predict --train`; subsequent
  predictions are tagged `trained-v1` automatically.

```bash
precc predict "<task description>"               # log a prediction
precc predict --record <id> <actual_tokens>       # close the loop
precc predict --train                             # fit trained-v1
precc predict --eval                              # MAPE per category
```

## Counterfactual Telemetry (v1.1, opt-in, dormant by default)

The hook can record a `(would-have-run, did-run, outcome)` triple per
Bash invocation to a SQLCipher-encrypted store at
`~/.local/share/precc/triples.db`. The stream is **opt-in only** —
disabled by default; you turn it on per machine via the `[counterfactual]`
section of `consent.toml` (CLI ceremony lands in a future release).
A daily-rotated salt + agent-class fingerprint keeps the data
re-identification-resistant; nothing leaves the machine until a separate
upload path is configured. The telemetry schema is designed for k-anonymity,
with a documented threat model.

## Install

```bash
curl -fsSL https://peria.ai/install.sh | bash
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
- **`~/.local/bin/`** — Installs `precc`, `precc-hook`, and `precc-learner` binaries

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

# Token-cost prediction (v1.1)
precc predict "<task description>"
precc predict --record <id> <actual_tokens>
precc predict --train      # fit trained-v1 once you have ≥ 10 actuals
precc predict --eval       # mean error / MAPE
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

- GitHub: https://github.com/peri-a-i/precc-cc
- ClawHub: https://clawhub.ai/skills/precc
- cocoindex-code: https://github.com/cocoindex-io/cocoindex-code
- RTK: https://github.com/rtk-ai/rtk

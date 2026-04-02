# PRECC — Predictive Error Correction for Claude Code

In a retrospective analysis of 89 real Claude Code sessions (3,078 commands), PRECC saved **2.5x more tokens than RTK alone** — **43% total reduction** vs 17% — by combining output compression with predictive error correction, comment blocking, and bash unwrapping. Ships as a single Rust binary.

## Install

Scan to get started:

<p align="center">
  <a href="https://peria.ai/go/"><img src="https://peria.ai/assets/precc-install-qr.png" alt="Install PRECC" width="160"></a>
</p>

### Option 1: Pre-built binary (recommended)

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/peria-ai/precc-cc/main/scripts/install.sh | bash
```

**Windows (PowerShell):**

```powershell
iwr -useb https://raw.githubusercontent.com/peria-ai/precc-cc/main/scripts/install.ps1 | iex
```

Then run:

```bash
precc init
```

### Option 2: Claude Code Plugin

```bash
claude plugin marketplace add peria-ai/precc
claude plugin install precc
```

Restart Claude Code to activate the plugin.

### Option 3: ClawHub Skill

```bash
clawhub install precc
```

## What It Does

### Pillar 1: Command Correction & Output Compression

- **Fixes wrong-directory commands** — Detects when `cargo build` or `npm test` is run in the wrong directory and prepends `cd /correct/path &&`
- **Prevents repeated failures** — Learns from past session failures and auto-corrects commands that would fail the same way
- **Compresses CLI output** — Rewrites commands to use [RTK](https://github.com/rtk-ai/rtk) for 60-90% smaller output, reducing context growth
- **Suggests GDB debugging** — When a command fails repeatedly, suggests `precc debug` instead of edit-compile-retry cycles

### Pillar 2: Semantic Code Search ([cocoindex-code](https://github.com/cocoindex-io/cocoindex-code))

PRECC's hook automatically intercepts recursive `grep` and `rg` commands. When a project has a cocoindex-code index, the hook redirects through AST-aware semantic search — saving ~70% of search output tokens. Built into the `precc-hook` binary; no extra scripts needed.

```bash
# Index your project (one-time)
ccc init && ccc index

# Search by meaning instead of text
ccc search "user session management"
ccc search --lang python "error handling"
```

### Pillar 3: Context File Compression

Strips filler words and verbose phrasing from always-loaded context files (CLAUDE.md, memory files). Since these files are sent with every API call, even small reductions compound across a session. Built into the `precc` binary.

```bash
# Preview savings
precc compress --dry-run

# Compress (backups saved as *.backup)
precc compress

# Revert to originals
precc compress --revert
```

### New in v0.2.6

- **Comment blocker** — Blocks `# ...` comment lines from executing as bash commands, eliminating no-op error output (~51K tokens saved historically)
- **Bash unwrap** — Strips unnecessary `bash -c "cmd"` wrappers to run commands directly, reducing subshell overhead
- **Nushell integration** (experimental) — Rewrites commands to use compact/structured output modes (`--message-format=short`, `--porcelain`, `-json`); set `PRECC_NUSHELL=1` to enable
- **What-if analysis** — `precc nushell what-if` replays historical sessions to compare bash vs RTK vs nushell token savings by usage category
- **Skill clustering** (**Pro**) — `precc skills cluster` scans installed skills, clusters by TF-IDF similarity, and recommends removing duplicates to save context tokens
- **Geofence compliance guard** (**Pro**) — Detects restricted IP regions and blocks Anthropic API interactions to protect accounts, suggests alternative LLMs for blocked regions

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

# View unified savings report (all three pillars)
precc savings

# What-if: compare token savings across bash, RTK, and nushell
precc nushell what-if

# Audit installed skills for overlap and recommend removals (Pro)
precc skills cluster
```

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
- [cocoindex-code](https://github.com/cocoindex-io/cocoindex-code) (optional, for AST-driven semantic search)

## Measured Results

Analyzed across 89 real Claude Code sessions, 3,078 bash calls:

| Metric | Value |
|--------|-------|
| **Token savings** | **43% total reduction** (vs 17% RTK alone) |
| **Failures prevented** | **352 / 358 (98%)** |
| **Bash calls improved** | **894 / 5,384 (17%)** |
| **Cache reads saved** | **988M / 1.67B tokens (59%)** |
| **Hook latency** | **2.93ms avg (1.77ms overhead)** |

## Pricing

PRECC is free for core features. Pro unlocks skill clustering, geofence compliance, and more.

| Plan | Price | Duration |
|------|-------|----------|
| **Community** | Free | Forever |
| **Pro (6-month)** | [$5](https://buy.stripe.com/5kQ14nb8r7u4bTb1Cj8k802) | 6 months |
| **Pro (annual)** | [$10](https://buy.stripe.com/9B6aEXekD5lW5uN5Sz8k801) | 12 months |

### How to subscribe

1. **Purchase** — Click a price link above and complete Stripe Checkout
2. **Check your email** — A license key will be sent automatically to your email
3. **Activate** — Run:
   ```bash
   precc license activate PRECC-XXXXX-XXXXX-XXXXX-XXXXX --email you@example.com
   ```
4. **Verify** (optional):
   ```bash
   precc license status
   ```

> **GitHub Sponsors:** `precc license activate --github` (coming soon)

## Acknowledgements

- [cocoindex-code](https://github.com/cocoindex-io/cocoindex-code) — AST-driven semantic code search engine
- [token-saver](https://clawhub.ai/skills/token-saver) — Context file compression patterns (MIT-0, by RubenAQuispe)
- [Nushell](https://github.com/nushell/nushell) — Structured shell for compact/machine-readable output, further improving on RTK compression
- [RTK](https://github.com/rtk-ai/rtk) — CLI output compression toolkit

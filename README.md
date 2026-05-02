# PRECC — Predictive Error Correction for Claude Code

Open-source Rust binary. Free forever. PRECC sits between Claude Code and your shell, compressing Bash output before it reaches the model and surfacing real measured savings live in your status bar. **22.6% measured token savings on Bash output across 213 ground-truth measurements**, with `lean-ctx` as the top-performing compression mode. Hook latency under 3ms.

## Install

```bash
curl -fsSL https://peria.ai/install.sh | bash
precc init
```

This installs PRECC plus its companion compression tools (`lean-ctx`, `rtk`, `nushell`, `cocoindex-code`) by default. To skip the companions:

```bash
curl -fsSL https://peria.ai/install.sh | bash -s -- --no-extras
```

**Windows (PowerShell):**

```powershell
iwr -useb https://peria.ai/install.ps1 | iex
```

The installer wires PRECC into `~/.claude/settings.json` (PreToolUse + PostToolUse hooks + statusLine), then **restart Claude Code** to activate.

### Alternative install paths

| Method | Command |
|---|---|
| Claude Code Plugin | `claude plugin marketplace add peria-ai/precc && claude plugin install precc` |
| ClawHub Skill | `clawhub install precc` |

## What you get

### Live status bar
Every Claude Code session shows real-time PRECC metrics:

```
$0.42 spent | 1.2M in/out | 📊 last cmd: −1.2K tok | PRECC: 7 fixes | 5.8ms avg | last session: 8.9K saved over 217 cmds (~$2.85)
```

| Segment | What it shows |
|---|---|
| `$0.42 spent` | Cumulative session cost (read directly from Claude Code's `/cost`) |
| `1.2M in/out` | Non-cached input + output tokens this session |
| `📊 last cmd:` | Real measured saving on the most recent Bash command |
| `PRECC: N fixes` | Corrections applied this session |
| `5.8ms avg` | Hook latency (p50) |
| `last session: N saved over M cmds (~$X.YZ)` | Lifetime measured tokens saved across all sessions, with an estimated USD value at your current per-token rate |

### Per-interaction reporting
Every measured Bash command also surfaces a live line in Claude's context:

```
📊 PRECC: 423 tokens used, 1247 saved (75%) via lean-ctx for `find /var`
```

Suppress with `PRECC_QUIET=1` if you prefer a quieter shell.

### What PRECC actually does

| Pillar | What it touches | Mechanism |
|---|---|---|
| **Bash output compression** | stdout/stderr of every Bash tool call | Adaptive selection across `lean-ctx`, `rtk`, `nushell`, and PRECC's own `diet` rewrites — picks the best mode per command class based on live measurements |
| **Wrong-directory fix** | `cargo`, `npm`, `git`, `make`, `python` outside their project root | Prepends `cd /correct/path &&` automatically |
| **Failure learning** | Commands that historically failed in your sessions | Auto-corrects them before they re-run |
| **Comment + bash unwrap** | `# comment` lines, `bash -c "cmd"` wrappers | Blocks no-op output, strips unnecessary subshells |
| **Semantic search** | Recursive `grep`/`rg` calls | Redirects to AST-aware [cocoindex-code](https://github.com/cocoindex-io/cocoindex-code) when an index exists |
| **Read filter** | Large or binary files | Auto-injects line limits, blocks binaries with a hint |
| **Context file compression** | `CLAUDE.md` and other always-loaded memory files | `precc compress` strips filler words; backups saved as `*.backup` |

### Real measured savings, not marketing numbers

PRECC re-runs the original (uncompressed) form of each Bash command on a budget and compares it to the actual (compressed) output. Every measurement is a row in the local `savings_measurements` table — the lifetime totals on precc.cc and in your status bar come from sums over those rows, not from estimated multipliers.

```bash
# View your own measured savings
precc savings

# Full breakdown including per-mode and per-skill
precc savings --all
```

## Honest cost framing

PRECC's status bar shows two cost-related numbers that **don't divide into a meaningful per-token rate**:

- **`$X.YZ spent`** — Read verbatim from Claude Code's `cost.total_cost_usd`. Includes base input, output, **cache reads, and cache creations**.
- **`N in/out`** — Non-cached input + output only. Cumulative cache token counts are not exposed in the statusline schema.

On long sessions with heavy file rereads, cache reads can be **10× the visible token count**. So `$383 spent | 1.2M in/out` is correct — it just means most of the cost came from cached tokens that aren't displayed. Verify any time with the built-in `/cost` slash command.

PRECC compresses **Bash output**, which is typically **10–25%** of total session tokens (the rest is Read/Edit/Write/thinking). Even if PRECC compressed 100% of Bash to zero, you'd save at most ~25% of session cost. The status bar's `bash X% of total` segment surfaces your actual share.

## Privacy & telemetry

- All PRECC databases are **AES-256 encrypted** via SQLCipher with a key derived from your machine ID and username (HKDF-SHA256). No passphrase required, no key stored on disk. Databases are unreadable on any other machine.
- Anonymous telemetry is **opt-in only** — `precc telemetry consent` to enable. When enabled, PRECC sends aggregated counters (no command text, no file paths) to peria.ai to populate the live stats on [precc.cc](https://precc.cc).
- Reports are deduplicated by a stable anonymous machine hash (SHA256 of machine-id + username) and an optional email hash, so multiple machines belonging to the same user are aggregated correctly.

## Auto-update

```bash
precc update             # check + update if newer version available
precc update --force     # force re-download even if same version
precc update --auto      # enable background auto-update via the daemon
```

`precc update` also reconciles `~/.claude/settings.json` (adds PostToolUse if missing) and back-fills any missing companion tools (`lean-ctx`, `rtk`, `nushell`, `ccc`) so existing users get the latest hook wiring on every update without re-running the installer.

## Documentation

Full user guide in **28 languages** at [precc.cc](https://precc.cc) — installation, savings interpretation, status bar reference, telemetry consent, hook pipeline internals, and FAQ.

## Pricing

| Plan | Price | Duration |
|------|-------|----------|
| **Community** | Free | Forever |
| **Pro (6-month)** | [$5](https://buy.stripe.com/5kQ14nb8r7u4bTb1Cj8k802) | 6 months |
| **Pro (annual)** | [$10](https://buy.stripe.com/9B6aEXekD5lW5uN5Sz8k801) | 12 months |

Pro unlocks `precc skills cluster` (TF-IDF skill deduplication), geofence compliance, and detailed `precc savings --all` breakdowns.

After purchase, a license key arrives by email; activate with:

```bash
precc license activate PRECC-XXXXX-XXXXX-XXXXX-XXXXX --email you@example.com
precc license status
```

## Acknowledgements

- [lean-ctx](https://github.com/yvgude/lean-ctx) — Deep Bash output compression (top-performing mode in live measurements)
- [RTK](https://github.com/rtk-ai/rtk) — Token-optimized CLI output rewrites
- [Nushell](https://github.com/nushell/nushell) — Structured shell for compact output
- [cocoindex-code](https://github.com/cocoindex-io/cocoindex-code) — AST-driven semantic search
- [token-saver](https://clawhub.ai/skills/token-saver) — Context file compression patterns (MIT-0, by RubenAQuispe)

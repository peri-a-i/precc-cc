# PRECC — Predictive Error Correction for Claude Code

Open-source Rust binary. Free forever. PRECC sits between Claude Code and your shell, compressing Bash output before it reaches the model, predicting token cost for any planned task, and surfacing real measured savings live in your status bar — in 28 languages. **22.6 % measured token savings on Bash output across 213 ground-truth measurements**, with `lean-ctx` as the top-performing compression mode. Hook latency under 3 ms.

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
| Claude Code Plugin | `claude plugin marketplace add peri-a-i/precc-cc && claude plugin install precc` |
| ClawHub Skill | `clawhub install precc` |

## What you get

### Live status bar

Every Claude Code session shows real-time PRECC metrics:

```
$0.42 spent | 1.2M in/out | bash 18% of total | PRECC: 7 fixes | 5.8ms avg | lifetime saved: 432.0K (~$1.30)
```

| Segment | What it shows |
|---|---|
| `$0.42 spent` | Cumulative session cost (read directly from Claude Code's `/cost`) |
| `1.2M in/out` | Non-cached input + output tokens this session |
| `bash 18% of total` | Share of session tokens that came from Bash output |
| `PRECC: N fixes` | Corrections applied this session |
| `5.8ms avg` | Hook latency (p50) |
| `lifetime saved: …` | Lifetime measured tokens saved across all sessions, with an estimated USD value at your current per-token rate |

### Status-line localization (28 languages)

Set `PRECC_LANG` and the same status line renders in your language. Right-to-left scripts work natively. The output below is verbatim from the v0.3.31 release binary on the same fake stdin:

```bash
PRECC_LANG=en   # $0.09 sub / $0.42 API | 15.5K in/out | bash 18% of total | PRECC: 23 fixes | 2.1ms avg
PRECC_LANG=zh   # $0.09 订阅 / $0.42 API | 15.5K 入/出 | bash 占总量 18% | PRECC: 修正 23 次 | 2.1ms 平均
PRECC_LANG=ar   # $0.09 اشتراك / $0.42 API | 15.5K دخل/خرج | bash 18% من المجموع | PRECC: 23 إصلاحات | 2.1ms متوسط
```

Any of 28 languages is accepted (English, Spanish, German, Simplified and Traditional Chinese, French, Portuguese, Japanese, Vietnamese, Dutch, Hungarian, Arabic, Persian, Turkish, Korean, Thai, Polish, Russian, Danish, Swedish, Finnish, Italian, Icelandic, Romanian, Czech). Burmese, Mongolian, and Tibetan ship with empty translation cells today and fall back to English at lookup time — same convention used by the precc.cc book; submit a translation pull request to fill them in.

Persist the choice by adding to `~/.config/precc/consent.toml`:

```toml
[ui]
preferred_language = "ja"
```

`PRECC_LANG` env var, when set, overrides the consent.toml value.

### Per-interaction reporting

Every measured Bash command also surfaces a live line in Claude's context:

```
PRECC: 423 tokens used, 1247 saved (75%) via lean-ctx for `find /var`
```

Suppress with `PRECC_QUIET=1` if you prefer a quieter shell.

### What PRECC actually does

Three pillars, all measured:

| Pillar | What it touches | Mechanism |
|---|---|---|
| **1. Command correction** | `cargo`, `npm`, `git`, `make`, `python` outside their project root; commands that historically failed in your sessions; `# comment` and `bash -c "…"` wrappers | Prepends `cd /correct/path &&`, auto-corrects learned-failure commands, blocks no-op output, strips unnecessary subshells |
| **2. Bash output compression** | stdout/stderr of every Bash tool call | Adaptive selection across `lean-ctx`, `rtk`, `nushell`, and PRECC's own `diet` rewrites — picks the best mode per command class based on live measurements |
| **3. Context file compression** | `CLAUDE.md` and other always-loaded memory files | `precc compress` strips filler words; backups saved as `*.backup` |

Plus targeted helpers that ride on top of the pillars:

| Helper | What it does |
|---|---|
| **Semantic search** | Recursive `grep`/`rg` calls redirect to AST-aware [cocoindex-code](https://github.com/cocoindex-io/cocoindex-code) when an index exists |
| **Read filter** | Auto-injects line limits on large files; blocks binaries with a hint |

### Token-cost prediction oracle (`precc predict`)

Predict the token cost of any multi-step task before you run it. Record the actual when it lands. PRECC keeps a labelled (planned → actual) dataset in a local SQLite oracle and trains its own predictor on it.

```bash
precc predict "<one-line task description>"      # log a prediction, returns row id
precc predict --record <id> <actual_tokens>       # close the loop
precc predict --train                             # fit trained-v1 once you have ~10 actuals
precc predict --eval                              # mean error / MAPE per category
precc predict --list                              # recent predictions
```

Two predictors ship side-by-side:

- **`heuristic-1`** — rule-based category × length estimator, available out of the box.
- **`trained-v1`** — closed-form ridge regression on `log10(actual_tokens + 1)` against intercept + `log10(description_length + 1)` + one-hot category dummies, λ = 1. Pure-Rust Cholesky solver, no Python, no external dependency. Coefficients persist to `~/.local/share/precc/predict_model.json`; new rows are tagged `trained-v1` automatically once trained, while old rows keep `heuristic-1` so `--eval` can compare predictors over time.

Per a 23-skill audit of ClawHub (`docs/symposium-plan/clawhub-competitor-survey.md`), **no peer skill on the registry publishes a planned-vs-actual token oracle** — `token-optimizer`, `token-saver`, `token-manager`, `token-guard` and `token-budget-monitor` all monitor *current/cumulative* usage and throttle. `precc predict --record` is unique on ClawHub as of 2026-05-09.

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

PRECC compresses **Bash output**, which is typically **10–25 %** of total session tokens (the rest is Read/Edit/Write/thinking). Even if PRECC compressed 100 % of Bash to zero, you'd save at most ~25 % of session cost. The status bar's `bash X% of total` segment surfaces your actual share.

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

Full user guide in **28 languages** at [precc.cc](https://precc.cc) — installation, savings interpretation, status bar reference, telemetry consent, hook pipeline internals, token-cost prediction (`precc predict`), and FAQ.

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

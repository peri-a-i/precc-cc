---
description: Show an auditable, reversible receipt of recent PRECC decisions — what was rewritten, why, and how to undo it
---

Run `precc receipt` and display the output to the user. This prints a per-decision, reversible ledger of PRECC's recent rewrites:

- **What changed** — each command's original → rewritten form, grouped by decision class (e.g. `lean-ctx-wrap`, `cd-prepend`, `nushell-wrap`).
- **Why** — the reason(s) and any skills that produced the rewrite.
- **How to reverse it** — every decision is content-addressed by `id` and undoable with `precc undo <id>`.

Useful flags:

- `precc receipt --since 7d` — widen the window (default `24h`).
- `precc receipt --limit 100` — show more decisions.
- `precc receipt --json` — emit the receipt as JSON for agents/dashboards.

This surface proves *what changed and that it's reversible*. It does not print a per-line token number — the rewrite log records the decision, not the compressed output's byte delta. For **measured** token totals, run `precc savings`.

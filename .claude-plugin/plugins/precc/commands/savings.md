---
description: Show PRECC unified savings report — command correction, output compression, semantic search, and context compression
---

Run `precc savings` and display the output to the user. This shows PRECC's estimated token savings across all three pillars:

1. **Pillar 1** — Command correction (CD prepends, skill activations, mined preventions) and RTK output compression.
2. **Pillar 2b** — Semantic search savings from grep/rg → cocoindex-code redirections.
3. **Pillar 3** — Context file compression savings (CLAUDE.md, memory files).

All metrics are now unified in `precc savings`. For full per-tool and per-skill breakdown, use `precc savings --all` (Pro).

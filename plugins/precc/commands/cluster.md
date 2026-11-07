---
description: Cluster installed skills by function, find overlaps, and recommend token-efficient replacements
---

Run `precc skills cluster` and display the output to the user. This scans all installed Claude Code skills (SKILL.md files from plugins, ClawHub, and local), clusters them by functional similarity using TF-IDF on their names and descriptions, monitors per-skill token consumption from session logs, and recommends removing redundant skills to reduce context token costs.

The output shows:
1. **Skill inventory** — all installed skills with their context token cost and source
2. **Functional clusters** — groups of skills that solve the same problem (similarity > threshold)
3. **Recommendations** — within each cluster, keep the most-used skill with good success rate, suggest removing the rest
4. **Potential savings** — total tokens per session recoverable by removing duplicates

If the user provides "$ARGUMENTS", pass it as flags. For example:
- `precc skills cluster` — default clustering (threshold=0.3)
- `precc skills cluster --threshold 0.5` — stricter clustering (fewer, tighter groups)

This is useful when:
- You've installed many skills and want to audit for overlap
- Context token budget is tight and you want to trim unused or redundant skills
- Comparing alternative skills that serve the same function (e.g., multiple code review skills)

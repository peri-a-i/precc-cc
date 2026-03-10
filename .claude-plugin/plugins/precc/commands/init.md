---
description: Initialize PRECC databases and load built-in skills
---

Run `precc init` to set up PRECC databases and load built-in automation skills. This creates:
- heuristics.db — automation skills database
- history.db — mined failure-fix pairs
- metrics.db — hook performance metrics

After init completes, suggest running `precc ingest --all` to mine existing session history.

---
description: Semantic code search powered by cocoindex-code (AST-driven)
---

Run `ccc search "$ARGUMENTS"` to perform AST-aware semantic code search across the current project. This uses cocoindex-code to find relevant code blocks by meaning, not just text matching.

If the index has not been built yet, first run `ccc init && ccc index` to create it.

Useful flags:
- `--lang python` — filter by language
- `--path 'src/**'` — filter by file path glob
- `--refresh` — update the index before searching
- `--limit N` — number of results (default 5)

Example: `ccc search --lang typescript "authentication middleware"`

---
description: Compress CLAUDE.md and context files to reduce token usage on every API call
---

Run `precc compress $ARGUMENTS` to compress context files in the current project.

This strips filler words and verbose phrasing from CLAUDE.md and .claude/memory/*.md files, reducing tokens loaded on every API call. Backups are saved as *.backup files.

Options:
- `--dry-run` — show what would change without modifying files
- `--revert` — restore original files from backups

If no arguments given, compresses all discoverable context files and logs savings.

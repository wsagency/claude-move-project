# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`clamp` (**CL**aude **A**I **M**ove **P**roject) is a bash utility that moves, fixes, lists, verifies, prunes, and manages Claude Code projects while preserving all session history and settings. It handles three interconnected data stores:

1. **Project folder** - The actual project directory with code and `.claude/` settings
2. **History folder** - `~/.claude/projects/[encoded-path]/` containing session JSONL files
3. **History index** - `~/.claude/history.jsonl` with project path references

The encoded path format converts `/path/to/dir` to `-path-to-dir`.

## Testing

Test locally by running with `--dry-run` flag:
```bash
./clamp ./test-project ~/new-location --dry-run
```

## Key Implementation Details

- Uses `set -euo pipefail` for strict error handling
- Implements atomic rollback via EXIT trap if any step fails
- Handles macOS vs Linux `sed -i` differences
- Path resolution works for both existing and non-existing destination paths
- Must be compatible with bash 3.2 (macOS default) — no associative arrays
- Encoded path format is lossy (can't decode back) — use history.jsonl as source of truth
- `_list_has` uses `grep -qFx --` (note `--` to handle values starting with `-`)

## Migration Sequence

The script performs operations in this order (critical for rollback):
1. Backup `history.jsonl`
2. Move project folder
3. Rename history folder in `~/.claude/projects/`, plus nested project
   folders (sub-projects, worktrees) verified via the `cwd` field in
   session files
4. Update path references in `history.jsonl`

Rollback reverses these steps if any operation fails.

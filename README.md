# clamp

**CL**aude **A**I **M**ove **P**roject

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS | Linux](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)](https://github.com/wsagency/claude-move-project#supported-platforms)

A bash utility that moves Claude Code projects while preserving all session history and settings.

## Features

- 📦 **Move** project folders to new locations
- 📂 **Move here** (`--here`) — move a project into the current directory
- 🔧 **Fix** (`--fix`) — repair broken references after manual `mv`
- 📋 **List** (`--list`) — show all Claude projects with status
- ✅ **Verify** (`--verify`) — health check for project references
- 🧹 **Prune** (`--prune`) — remove orphaned session folders
- ℹ️ **Info** (`--info`) — detailed info about a single project
- 🗑️ **Remove** projects and all associated session data (`--remove`)
- 📤 **Pack** projects into portable `.claudepack` archives (`--pack`)
- 📥 **Unpack** archives with automatic path rewriting (`--unpack`)
- 🗂️ Auto-create parent directories with `-p`/`--parents`
- 🔄 Automatically migrates session history from `~/.claude/projects/`
- 📝 Updates all path references in `~/.claude/history.jsonl`
- 🛡️ Atomic rollback if any step fails
- 👀 Dry-run mode to preview changes before execution

## Installation

### Homebrew (macOS/Linux)

```bash
brew install wsagency/tap/clamp
```

### Manual

```bash
git clone https://github.com/wsagency/claude-move-project.git
cd claude-move-project
chmod +x clamp
```

Optionally, add to your PATH:

```bash
sudo ln -s "$(pwd)/clamp" /usr/local/bin/clamp
```

## Usage

```bash
# Move a project
clamp <source> <destination> [options]

# Move project into current directory
clamp --here <source>

# Move to deeply nested path (auto-create parents)
clamp <source> <destination> -p

# Fix broken references after manual mv
clamp --fix
clamp --fix <new-path>
clamp --fix --from <old-path> --to <new-path>

# List all Claude projects
clamp --list [--json]

# Health check
clamp --verify

# Remove orphaned session folders
clamp --prune

# Project info
clamp --info <project-path>

# Remove a project and all session data
clamp --remove <project-path>

# Pack a project into a portable archive
clamp --pack <project-path> [archive-path]

# Unpack an archive to a new location
clamp --unpack <archive-path> <destination>
```

### Examples

```bash
# Preview what would happen (recommended first step)
clamp ./my-project ~/new-location --dry-run

# Move a project (specifying full destination path)
clamp ./my-project ~/new-location/my-project

# Move into current directory
cd ~/new-location && clamp --here ~/old/my-project

# Move to nested path that doesn't exist yet
clamp ./my-project ~/deep/nested/new/path -p

# Move into an existing directory (mv-like behavior)
clamp ./my-project ~/projects

# Move without confirmation prompt
clamp ./my-project ~/new-location --force

# Fix after manual mv (most common scenario)
mv ~/old/my-project ~/new/my-project
clamp --fix ~/new/my-project       # auto-detect old path
clamp --fix --from ~/old/my-project --to ~/new/my-project

# List all projects and their status
clamp --list
clamp --list --json

# Check health of all project references
clamp --verify

# Remove orphaned session folders
clamp --prune
clamp --prune --dry-run

# Get detailed info about a project
clamp --info ./my-project

# Remove project and all session data
clamp --remove ./my-project

# Pack/unpack project for transfer
clamp --pack ./my-project
clamp --unpack backup.claudepack ~/new-location
```

### Destination Behavior

The destination argument works like `mv`:

- If destination **doesn't exist**: Creates it as the new project location
- If destination **is an existing directory**: Moves the project *into* that directory

```bash
# Destination doesn't exist - creates ~/new-location as the project
clamp ./my-app ~/new-location

# ~/projects exists - moves to ~/projects/my-app
clamp ./my-app ~/projects
```

### Options

| Option | Description |
|--------|-------------|
| `--here` | Move project into current directory |
| `--fix` | Repair broken references after manual mv |
| `--list` | List all Claude projects with status |
| `--verify` | Health check for project references |
| `--prune` | Remove orphaned session folders |
| `--info` | Show detailed info about a project |
| `--remove` | Delete project and all Claude session data |
| `--pack` | Archive project into .claudepack file |
| `--unpack` | Restore archive to destination |
| `-p, --parents` | Create parent directories as needed |
| `-n, --dry-run` | Preview changes without executing |
| `-f, --force` | Skip confirmation prompt |
| `--json` | Output in JSON format (for --list) |
| `--from <path>` | Original path (for --fix) |
| `--to <path>` | New path (for --fix) |
| `--no-backup` | Skip backup of history.jsonl |
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help message |
| `--version` | Show version |

## 🔍 How It Works

Claude Code stores project data in three locations:

1. **Project folder** - Your actual project with `.claude/` settings
2. **History folder** - `~/.claude/projects/[encoded-path]/` with session JSONL files
3. **History index** - `~/.claude/history.jsonl` with project path references

This script handles all three, ensuring your session history follows your project.

If you use a custom config directory via `CLAUDE_CONFIG_DIR`, clamp respects it automatically:

```bash
CLAUDE_CONFIG_DIR=~/custom-claude-config clamp ./my-project ~/new-location
```

### 🔄 Migration Sequence

1. Backup `history.jsonl`
2. Move project folder to destination
3. Rename history folder in `~/.claude/projects/`
4. Update path references in `history.jsonl`

If any step fails, all changes are automatically rolled back.

### 🔧 Fix Operation

The most common scenario: you already moved a folder with `mv` and Claude sessions broke.

```bash
# Auto-detect: scans for broken entries, tries to match by project name
clamp --fix

# Point to the new location: auto-finds the broken old entry
clamp --fix ~/new/location/my-project

# Explicit: specify both old and new paths
clamp --fix --from ~/old/path --to ~/new/path
```

### 📦 Archive Format (.claudepack)

The `--pack` command creates a tar.gz archive with this structure:

```
project-name.claudepack
├── manifest.json        # Metadata (version, original path, timestamp)
├── project/             # Project files including .claude/ settings
├── sessions/            # Session JSONL files from ~/.claude/projects/
└── history-entries.jsonl  # Relevant entries from history.jsonl
```

When unpacking, paths are automatically rewritten to match the new destination.

## 🧪 Testing

Run the test suite to verify the script works correctly:

```bash
# Run all tests
./test.sh

# Run a specific test
./test.sh test_basic_move
```

The test suite covers:
- Basic move operations
- Relative path resolution
- mv-like destination behavior
- Special characters (brackets, spaces, dots)
- Symlink handling
- Dry-run mode
- Error conditions (missing source, existing dest)
- Backup/rollback functionality
- `--list` (basic, JSON, empty, broken projects)
- `--here` mode
- `--parents` flag
- `--verify` (healthy and broken states)
- `--info` output
- `--fix` (explicit paths, auto-detect, nothing broken)
- `--prune` (orphaned folders, nothing to prune, dry-run)

## 🖥️ Supported Platforms

| Platform | Status |
|----------|--------|
| macOS | ✅ Fully supported |
| Linux | ✅ Supported |
| Windows | ⚠️ Via WSL or Git Bash |

### Windows Users

This script requires a bash environment. Windows users can run it using:

**Option 1: WSL2 (Recommended)**
1. Install WSL2: `wsl --install` in PowerShell (admin)
2. Open your WSL distro (e.g., Ubuntu)
3. Navigate to your project: `cd /mnt/c/Users/YourName/projects/myproject`
4. Run: `./clamp ./my-project /mnt/c/new-location`

**Option 2: Git Bash**
1. Install [Git for Windows](https://git-scm.com/download/win) (includes Git Bash)
2. Open Git Bash
3. Navigate to your project and run the script

## Disclaimer

**USE AT YOUR OWN RISK**

- This tool has been tested on macOS and should work on Linux
- Windows users must use WSL or Git Bash (see above)
- Always run with `--dry-run` first to preview changes
- Consider backing up your `~/.claude/` directory before use
- The authors are not responsible for any data loss

## Attribution

Created by [ws.agency](https://ws.agency)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 WEB Solutions Ltd. (ws.agency) & Kristijan Lukačin

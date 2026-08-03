# clamp

**CL**aude **A**I **M**ove **P**roject

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS | Linux](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)](https://github.com/wsagency/claude-move-project#supported-platforms)
[![CI](https://github.com/wsagency/claude-move-project/actions/workflows/ci.yml/badge.svg)](https://github.com/wsagency/claude-move-project/actions/workflows/ci.yml)

A bash utility that moves Claude Code projects while preserving all session history and settings.

## Features

- **Move** project folders to new locations
- **Move here** (`--here`): move a project into the current directory
- **Fix** (`--fix`): repair broken references after manual `mv`
- **List** (`--list`): show all Claude projects with status
- **Verify** (`--verify`): health check for project references
- **Prune** (`--prune`): remove orphaned session folders
- **Info** (`--info`): detailed info about a single project
- **Remove** projects and all associated session data (`--remove`)
- **Pack** projects into portable `.claudepack` archives (`--pack`)
- **Unpack** archives with automatic path rewriting (`--unpack`)
- Auto-create parent directories with `-p`/`--parents`
- Automatically migrates session history from `~/.claude/projects/`
- Updates all path references in `~/.claude/history.jsonl`
- Atomic rollback if any step fails
- Dry-run mode to preview changes before execution

## Installation

### Quick install (curl)

Downloads the latest release, verifies its SHA-256 checksum and installs to `/usr/local/bin` (or `~/.local/bin` if that is not writable):

```bash
curl -fsSL https://raw.githubusercontent.com/wsagency/claude-move-project/main/install.sh | bash
```

Options via environment variables:

```bash
# Pin a specific version
CLAMP_VERSION=1.4.1 curl -fsSL https://raw.githubusercontent.com/wsagency/claude-move-project/main/install.sh | bash

# Choose the install directory
CLAMP_BIN_DIR=~/.local/bin curl -fsSL https://raw.githubusercontent.com/wsagency/claude-move-project/main/install.sh | bash
```

To update, run the same command again. To uninstall, delete the `clamp` binary from the install directory.

### Homebrew (macOS/Linux)

```bash
brew install wsagency/tap/clamp
```

Update with `brew upgrade clamp`. The tap is refreshed automatically on every release (see [Releasing](#releasing)).

### AUR (Arch Linux)

```bash
# with an AUR helper
yay -S clamp
```

Alternatively, download the `PKGBUILD` asset from the [latest release](https://github.com/wsagency/claude-move-project/releases/latest) and run `makepkg -si`.

### Debian/Ubuntu

Each release ships a `.deb` package:

```bash
curl -fsSLO https://github.com/wsagency/claude-move-project/releases/latest/download/clamp_1.4.1_all.deb
sudo apt install ./clamp_1.4.1_all.deb
```

Replace the version with the one shown on the [releases page](https://github.com/wsagency/claude-move-project/releases/latest). There is no apt repository; update by installing the newer `.deb`.

### Manual

```bash
git clone https://github.com/wsagency/claude-move-project.git
cd claude-move-project
chmod +x clamp
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

## How It Works

Claude Code stores project data in three locations:

1. **Project folder** - Your actual project with `.claude/` settings
2. **History folder** - `~/.claude/projects/[encoded-path]/` with session JSONL files
3. **History index** - `~/.claude/history.jsonl` with project path references

This script handles all three, ensuring your session history follows your project.

### Migration Sequence

1. Backup `history.jsonl`
2. Move project folder to destination
3. Rename history folder in `~/.claude/projects/`
4. Update path references in `history.jsonl`

If any step fails, all changes are automatically rolled back.

### Fix Operation

The most common scenario: you already moved a folder with `mv` and Claude sessions broke.

```bash
# Auto-detect: scans for broken entries, tries to match by project name
clamp --fix

# Point to the new location: auto-finds the broken old entry
clamp --fix ~/new/location/my-project

# Explicit: specify both old and new paths
clamp --fix --from ~/old/path --to ~/new/path
```

### Archive Format (.claudepack)

The `--pack` command creates a tar.gz archive with this structure:

```
project-name.claudepack
├── manifest.json        # Metadata (version, original path, timestamp)
├── project/             # Project files including .claude/ settings
├── sessions/            # Session JSONL files from ~/.claude/projects/
└── history-entries.jsonl  # Relevant entries from history.jsonl
```

When unpacking, paths are automatically rewritten to match the new destination.

## Testing

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

Continuous integration runs the suite on Ubuntu and macOS, plus `shellcheck`, on every push and pull request (`.github/workflows/ci.yml`). The macOS job matters because it runs bash 3.2, the oldest version clamp supports.

## Releasing

For maintainers. The whole flow is: bump, tag, push. GitHub Actions does the rest.

```bash
# 1. Bump the version, run tests, commit and tag (nothing is pushed yet)
scripts/release.sh 1.5.0

# 2. Publish
git push origin main v1.5.0
```

The version in the `clamp` script (`VERSION="..."`) is the single source of truth. `scripts/release.sh` updates it, runs `./test.sh`, commits `chore: release v1.5.0` and creates the annotated tag `v1.5.0`.

### What the Release workflow does

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which:

1. Fails if the tag does not match `VERSION` inside the `clamp` script.
2. Runs the test suite.
3. Builds all artifacts with `scripts/build-dist.sh`.
4. Creates a GitHub release with generated notes and these assets:

| Asset | Purpose |
|-------|---------|
| `clamp` | Raw script, downloaded by `install.sh` |
| `clamp-X.Y.Z.tar.gz` | Source tarball for Homebrew and the AUR |
| `clamp_X.Y.Z_all.deb` | Debian/Ubuntu package |
| `clamp.rb` | Homebrew formula pinned to this release |
| `PKGBUILD` | AUR build file pinned to this release |
| `checksums.txt` | SHA-256 checksums of all assets |

5. If the `HOMEBREW_TAP_TOKEN` secret is set, commits `clamp.rb` to `<owner>/homebrew-tap` at `Formula/clamp.rb`.

You can build the same artifacts locally with `scripts/build-dist.sh` (output goes to `dist/`, which is gitignored). The formula and PKGBUILD are rendered from the templates in `packaging/`.

### One-time setup per channel

- **curl install and .deb**: nothing to set up. They work as soon as the first release exists.
- **Homebrew**: the tap repository (`wsagency/homebrew-tap`) already exists. Add a repository secret `HOMEBREW_TAP_TOKEN` here (a fine-grained personal access token with read/write contents permission on `homebrew-tap`) and the workflow keeps `Formula/clamp.rb` up to date. Users run `brew install wsagency/tap/clamp`.
- **AUR**: publishing is manual because it needs your personal AUR SSH key. After each release, download the `PKGBUILD` asset, then:

  ```bash
  git clone ssh://aur@aur.archlinux.org/clamp.git aur-clamp
  cp PKGBUILD aur-clamp/
  cd aur-clamp
  makepkg --printsrcinfo > .SRCINFO
  git add PKGBUILD .SRCINFO
  git commit -m "Update to 1.5.0"
  git push
  ```

  This can be automated later with an AUR deploy action and an SSH key secret.
- **apt**: the `.deb` asset covers direct installs. A real apt repository (PPA or self-hosted) is out of scope for now.

### For downstream package maintainers

Every release provides stable URLs:

```
https://github.com/wsagency/claude-move-project/releases/download/vX.Y.Z/clamp-X.Y.Z.tar.gz
https://github.com/wsagency/claude-move-project/releases/latest/download/checksums.txt
```

The tarball contains a `clamp-X.Y.Z/` directory with the `clamp` script, `LICENSE` and `README.md`. The `clamp.rb` and `PKGBUILD` assets already contain the correct version and SHA-256, so packaging for another distribution usually means adapting one of them.

## Supported Platforms

| Platform | Status |
|----------|--------|
| macOS | Fully supported |
| Linux | Supported |
| Windows | Via WSL or Git Bash |

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

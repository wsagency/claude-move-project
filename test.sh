#!/usr/bin/env bash
#
# test.sh - Test suite for clamp
#
# Usage: ./test.sh [test_name]
#   Run all tests: ./test.sh
#   Run single test: ./test.sh test_basic_move
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test directory setup
TEST_DIR=""
MOCK_CLAUDE_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/clamp"

# Real $HOME captured at script load (each test overrides HOME to its sandbox).
ORIGINAL_HOME="$HOME"

# Source clamp so tests can call its helpers; sourceability guard skips main().
source "$SCRIPT"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

# Setup test environment
setup_test_env() {
    # Sandbox under $HOME, not /tmp.
    # (MSYS auto-aliases /tmp cd-paths to forward-slash format).
    TEST_DIR=$(TMPDIR="$ORIGINAL_HOME" mktemp -d -t clamp-test.XXXXXX)
    MOCK_CLAUDE_DIR="$TEST_DIR/.claude"
    mkdir -p "$MOCK_CLAUDE_DIR/projects"
    touch "$MOCK_CLAUDE_DIR/history.jsonl"

    # Export for the script to use
    export HOME="$TEST_DIR"
}

# Cleanup test environment
cleanup_test_env() {
    # Return to original directory first (in case test changed cwd)
    cd "$SCRIPT_DIR" 2>/dev/null || true
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Create a mock project with history
create_mock_project() {
    local project_path="$1"
    local project_name="${2:-test-project}"

    mkdir -p "$project_path"
    mkdir -p "$project_path/.claude"
    echo "# Test Project" > "$project_path/README.md"
    echo "test content" > "$project_path/.claude/settings.json"

    # Create encoded history folder
    local abs_path
    abs_path=$(cd "$project_path" && pwd)
    local encoded="${abs_path//\//-}"

    mkdir -p "$MOCK_CLAUDE_DIR/projects/$encoded"
    echo '{"type":"session","data":"test"}' > "$MOCK_CLAUDE_DIR/projects/$encoded/session1.jsonl"

    # Add entry to history.jsonl
    echo "{\"project\":\"$abs_path\",\"session\":\"session1\"}" >> "$MOCK_CLAUDE_DIR/history.jsonl"
}

# create_mock_project, adjusted for Windows
# (embeds a path reference in session JSONL for rewrite testing)
create_mock_windows_project() {
    local project_path="$1"

    mkdir -p "$project_path"
    mkdir -p "$project_path/.claude"
    echo "# Test Project" > "$project_path/README.md"
    echo "test content" > "$project_path/.claude/settings.json"

    local saved_encoding="$PATH_ENCODING"
    PATH_ENCODING="windows"
    local win_abs win_encoded win_hist
    win_abs=$(get_absolute_path "$project_path")
    win_encoded=$(encode_path "$win_abs")
    win_hist=$(to_history_form "$win_abs")
    PATH_ENCODING="$saved_encoding"

    mkdir -p "$MOCK_CLAUDE_DIR/projects/$win_encoded"
    echo "{\"type\":\"session\",\"cwd\":\"$win_hist\",\"data\":\"test\"}" \
        > "$MOCK_CLAUDE_DIR/projects/$win_encoded/session1.jsonl"

    # Add entry to history.jsonl with Windows-form path
    echo "{\"project\":\"$win_hist\",\"session\":\"session1\"}" \
        >> "$MOCK_CLAUDE_DIR/history.jsonl"
}

# Assert file exists
assert_exists() {
    local path="$1"
    local msg="${2:-File should exist: $path}"
    if [[ -e "$path" ]]; then
        return 0
    else
        echo "  Assertion failed: $msg"
        return 1
    fi
}

# Assert file does not exist
assert_not_exists() {
    local path="$1"
    local msg="${2:-File should not exist: $path}"
    if [[ ! -e "$path" ]]; then
        return 0
    else
        echo "  Assertion failed: $msg"
        return 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    local path="$1"
    local msg="${2:-Directory should exist: $path}"
    if [[ -d "$path" ]]; then
        return 0
    else
        echo "  Assertion failed: $msg"
        return 1
    fi
}

# Assert file contains string
assert_contains() {
    local file="$1"
    local pattern="$2"
    local msg="${3:-File should contain: $pattern}"
    if grep -qF -- "$pattern" "$file" 2>/dev/null; then
        return 0
    else
        echo "  Assertion failed: $msg"
        return 1
    fi
}

# Assert file does not contain string
assert_not_contains() {
    local file="$1"
    local pattern="$2"
    local msg="${3:-File should not contain: $pattern}"
    if ! grep -qF -- "$pattern" "$file" 2>/dev/null; then
        return 0
    else
        echo "  Assertion failed: $msg"
        return 1
    fi
}

# Assert two strings are equal
assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-Expected [$expected] but got [$actual]}"
    if [[ "$actual" == "$expected" ]]; then
        return 0
    else
        echo "  Assertion failed: $msg"
        return 1
    fi
}

# Assert command fails
assert_fails() {
    local msg="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        return 0
    else
        echo "  Assertion failed: $msg"
        return 1
    fi
}

# Run a single test with setup/teardown
run_test() {
    local test_name="$1"
    log_test "Running: $test_name"

    setup_test_env

    local result=0
    if $test_name; then
        log_pass "$test_name"
    else
        log_fail "$test_name"
        result=1
    fi

    cleanup_test_env
    return $result
}

# ============================================================================
# TEST CASES
# ============================================================================

test_basic_move() {
    # Create source project
    create_mock_project "$TEST_DIR/source-project"
    local source_abs="$TEST_DIR/source-project"
    local dest_abs="$TEST_DIR/dest-project"

    # Run migration
    "$SCRIPT" "$source_abs" "$dest_abs" -f

    # Verify project moved
    assert_not_exists "$source_abs" "Source should be gone" || return 1
    assert_dir_exists "$dest_abs" "Destination should exist" || return 1
    assert_exists "$dest_abs/README.md" "README should be moved" || return 1
    assert_exists "$dest_abs/.claude/settings.json" "Settings should be moved" || return 1

    # Verify history folder renamed
    local old_encoded="${source_abs//\//-}"
    local new_encoded="${dest_abs//\//-}"
    assert_not_exists "$MOCK_CLAUDE_DIR/projects/$old_encoded" "Old history folder should be gone" || return 1
    assert_dir_exists "$MOCK_CLAUDE_DIR/projects/$new_encoded" "New history folder should exist" || return 1

    # Verify history.jsonl updated
    assert_not_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$source_abs" "Old path should not be in history" || return 1
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$dest_abs" "New path should be in history" || return 1
}

test_relative_source() {
    # Create source project
    mkdir -p "$TEST_DIR/workspace"
    create_mock_project "$TEST_DIR/workspace/my-app"

    # Run from workspace with relative source
    (
        cd "$TEST_DIR/workspace"
        "$SCRIPT" "./my-app" "$TEST_DIR/moved-app" -f
    )

    assert_not_exists "$TEST_DIR/workspace/my-app" "Source should be gone" || return 1
    assert_dir_exists "$TEST_DIR/moved-app" "Destination should exist" || return 1
}

test_relative_dest() {
    # Create source project
    mkdir -p "$TEST_DIR/workspace"
    create_mock_project "$TEST_DIR/workspace/project"
    mkdir -p "$TEST_DIR/workspace/subdir"

    # Run with relative destination
    (
        cd "$TEST_DIR/workspace"
        "$SCRIPT" "$TEST_DIR/workspace/project" "./subdir/renamed" -f
    )

    assert_not_exists "$TEST_DIR/workspace/project" "Source should be gone" || return 1
    assert_dir_exists "$TEST_DIR/workspace/subdir/renamed" "Destination should exist" || return 1
}

test_dest_is_directory() {
    # Create source project
    create_mock_project "$TEST_DIR/my-project"

    # Create destination directory (should move INTO it)
    mkdir -p "$TEST_DIR/target-dir"

    "$SCRIPT" "$TEST_DIR/my-project" "$TEST_DIR/target-dir" -f

    # Should be moved INTO target-dir, not replace it
    assert_not_exists "$TEST_DIR/my-project" "Source should be gone" || return 1
    assert_dir_exists "$TEST_DIR/target-dir/my-project" "Should be moved into target dir" || return 1
    assert_exists "$TEST_DIR/target-dir/my-project/README.md" "Files should be in new location" || return 1
}

test_special_chars_brackets() {
    # Create project with brackets in name
    create_mock_project "$TEST_DIR/project [test]"
    local source_abs="$TEST_DIR/project [test]"
    local dest_abs="$TEST_DIR/renamed [test]"

    "$SCRIPT" "$source_abs" "$dest_abs" -f

    assert_not_exists "$source_abs" "Source should be gone" || return 1
    assert_dir_exists "$dest_abs" "Destination should exist" || return 1

    # Verify history was updated correctly
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$dest_abs" "New path should be in history" || return 1
}

test_special_chars_spaces() {
    # Create project with spaces in name
    create_mock_project "$TEST_DIR/my project name"
    local source_abs="$TEST_DIR/my project name"
    local dest_abs="$TEST_DIR/new project name"

    "$SCRIPT" "$source_abs" "$dest_abs" -f

    assert_not_exists "$source_abs" "Source should be gone" || return 1
    assert_dir_exists "$dest_abs" "Destination should exist" || return 1
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$dest_abs" "New path should be in history" || return 1
}

test_special_chars_dots() {
    # Create project with dots in name
    create_mock_project "$TEST_DIR/my.project.v1.0"
    local source_abs="$TEST_DIR/my.project.v1.0"
    local dest_abs="$TEST_DIR/my.project.v2.0"

    "$SCRIPT" "$source_abs" "$dest_abs" -f

    assert_not_exists "$source_abs" "Source should be gone" || return 1
    assert_dir_exists "$dest_abs" "Destination should exist" || return 1
}

test_symlink_source() {
    # Create actual project
    create_mock_project "$TEST_DIR/real-project"

    # Create symlink to it
    ln -s "$TEST_DIR/real-project" "$TEST_DIR/link-project"

    # Skip if FS lacks real symlinks (MSYS without admin: `ln -s` makes a copy).
    if [[ ! -L "$TEST_DIR/link-project" ]]; then
        log_skip "Filesystem doesn't support symlinks (e.g. MSYS without admin), skipping"
        return 0
    fi

    # Move the symlink (should warn but proceed)
    local output
    output=$("$SCRIPT" "$TEST_DIR/link-project" "$TEST_DIR/moved-link" -f 2>&1)

    if ! echo "$output" | grep -q "symlink"; then
        echo "  Should warn about symlink"
        echo "  Output was: $output"
        return 1
    fi

    # The symlink should have been moved, not the target
    assert_not_exists "$TEST_DIR/link-project" "Symlink source should be gone" || return 1
    assert_dir_exists "$TEST_DIR/real-project" "Original project should still exist" || return 1
}

test_dry_run() {
    # Create source project
    create_mock_project "$TEST_DIR/dry-project"
    local source_abs="$TEST_DIR/dry-project"
    local dest_abs="$TEST_DIR/dry-dest"

    # Run with --dry-run
    "$SCRIPT" "$source_abs" "$dest_abs" --dry-run

    # Nothing should have changed
    assert_dir_exists "$source_abs" "Source should still exist" || return 1
    assert_not_exists "$dest_abs" "Destination should not exist" || return 1

    # History should be unchanged
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$source_abs" "History should still have old path" || return 1
}

test_nonexistent_source() {
    # Try to move nonexistent source
    assert_fails "Should fail with nonexistent source" \
        "$SCRIPT" "$TEST_DIR/does-not-exist" "$TEST_DIR/dest" -f
}

test_dest_exists() {
    # Create source and destination
    create_mock_project "$TEST_DIR/source"
    mkdir -p "$TEST_DIR/dest-exists"
    touch "$TEST_DIR/dest-exists/file.txt"

    # Try to move to existing destination (not a directory case - exact path exists)
    # First, move source into dest-exists (mv-like behavior)
    "$SCRIPT" "$TEST_DIR/source" "$TEST_DIR/dest-exists" -f

    # Should succeed by moving INTO the directory
    assert_dir_exists "$TEST_DIR/dest-exists/source" "Should move into existing dir" || return 1
}

test_dest_file_exists() {
    # Create source
    create_mock_project "$TEST_DIR/source"

    # Create a file (not directory) at destination path
    touch "$TEST_DIR/dest-file"

    # Should fail - destination exists but is a file
    # Note: This might need to be handled differently depending on implementation
    assert_fails "Should fail when destination is a file" \
        "$SCRIPT" "$TEST_DIR/source" "$TEST_DIR/dest-file" -f
}

test_missing_parent() {
    # Create source project
    create_mock_project "$TEST_DIR/source"

    # Try to move to location where parent doesn't exist
    assert_fails "Should fail when parent doesn't exist" \
        "$SCRIPT" "$TEST_DIR/source" "$TEST_DIR/nonexistent/subdir/dest" -f
}

test_no_history() {
    # Create project without history
    mkdir -p "$TEST_DIR/no-history-project"
    echo "# Test" > "$TEST_DIR/no-history-project/README.md"

    # Should still move the project folder (with warning)
    local output
    output=$("$SCRIPT" "$TEST_DIR/no-history-project" "$TEST_DIR/moved-no-history" -f 2>&1)

    if ! echo "$output" | grep -q "No Claude history"; then
        echo "  Should warn about missing history"
        echo "  Output was: $output"
        return 1
    fi

    assert_not_exists "$TEST_DIR/no-history-project" "Source should be gone" || return 1
    assert_dir_exists "$TEST_DIR/moved-no-history" "Destination should exist" || return 1
}

test_verbose_output() {
    # Create source project
    create_mock_project "$TEST_DIR/verbose-test"

    # Run with verbose flag
    local output
    output=$("$SCRIPT" "$TEST_DIR/verbose-test" "$TEST_DIR/verbose-dest" -f -v 2>&1)

    # Check for verbose output
    if echo "$output" | grep -q "\[VERBOSE\]"; then
        return 0
    else
        echo "  Verbose output not found"
        return 1
    fi
}

test_backup_created() {
    # Create source project
    create_mock_project "$TEST_DIR/backup-test"

    # Run migration
    "$SCRIPT" "$TEST_DIR/backup-test" "$TEST_DIR/backup-dest" -f

    # Check backup was created
    local backup_count
    backup_count=$(ls "$MOCK_CLAUDE_DIR"/history.jsonl.backup.* 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$backup_count" -ge 1 ]]; then
        return 0
    else
        echo "  Backup file not found"
        return 1
    fi
}

test_no_backup_flag() {
    # Create source project
    create_mock_project "$TEST_DIR/no-backup-test"

    # Run migration with --no-backup
    "$SCRIPT" "$TEST_DIR/no-backup-test" "$TEST_DIR/no-backup-dest" -f --no-backup

    # Check no backup was created
    local backup_count
    backup_count=$(ls "$MOCK_CLAUDE_DIR"/history.jsonl.backup.* 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$backup_count" -eq 0 ]]; then
        return 0
    else
        echo "  Backup file should not exist"
        return 1
    fi
}

test_same_source_dest() {
    # Create source project
    create_mock_project "$TEST_DIR/same-project"

    # Try to move to same location
    assert_fails "Should fail when source and dest are same" \
        "$SCRIPT" "$TEST_DIR/same-project" "$TEST_DIR/same-project" -f
}

# ============================================================================
# NEW FEATURE TESTS (v1.2.0)
# ============================================================================

test_list_basic() {
    # Create two projects
    create_mock_project "$TEST_DIR/project-a"
    create_mock_project "$TEST_DIR/project-b"

    # Run --list
    local output
    output=$("$SCRIPT" --list 2>&1)

    # Should show both projects
    if echo "$output" | grep -q "project-a" && echo "$output" | grep -q "project-b"; then
        return 0
    else
        echo "  Expected both projects in output"
        echo "  Output: $output"
        return 1
    fi
}

test_list_json() {
    # Create a project
    create_mock_project "$TEST_DIR/json-project"

    # Run --list --json
    local output
    output=$("$SCRIPT" --list --json 2>&1)

    # Should be valid JSON-ish (starts with [)
    if echo "$output" | grep -q '^\['; then
        return 0
    else
        echo "  Expected JSON output starting with ["
        echo "  Output: $output"
        return 1
    fi
}

test_list_empty() {
    # No projects created — empty env
    local output
    output=$("$SCRIPT" --list 2>&1)

    if echo "$output" | grep -q "No Claude projects found"; then
        return 0
    else
        echo "  Expected 'No Claude projects found' message"
        echo "  Output: $output"
        return 1
    fi
}

test_list_broken_project() {
    # Create project then delete the folder (simulate manual rm)
    create_mock_project "$TEST_DIR/broken-project"
    local abs_path
    abs_path=$(cd "$TEST_DIR/broken-project" && pwd)
    rm -rf "$TEST_DIR/broken-project"

    local output
    output=$("$SCRIPT" --list 2>&1)

    # Should show as broken/missing
    if echo "$output" | grep -q "missing"; then
        return 0
    else
        echo "  Expected 'missing' marker for broken project"
        echo "  Output: $output"
        return 1
    fi
}

test_here_mode() {
    # Create source project
    create_mock_project "$TEST_DIR/source-for-here"
    local source_abs="$TEST_DIR/source-for-here"

    # Create target dir and run --here from it
    mkdir -p "$TEST_DIR/target-dir"
    (
        cd "$TEST_DIR/target-dir"
        "$SCRIPT" --here "$source_abs" -f
    )

    assert_not_exists "$source_abs" "Source should be gone" || return 1
    assert_dir_exists "$TEST_DIR/target-dir/source-for-here" "Project should be in target dir" || return 1
    assert_exists "$TEST_DIR/target-dir/source-for-here/README.md" "Files should be moved" || return 1
}

test_parents_flag() {
    # Create source project
    create_mock_project "$TEST_DIR/parents-source"
    local source_abs="$TEST_DIR/parents-source"

    # Move to deeply nested non-existent path with -p
    "$SCRIPT" "$source_abs" "$TEST_DIR/deep/nested/new/location" -f -p

    assert_not_exists "$source_abs" "Source should be gone" || return 1
    assert_dir_exists "$TEST_DIR/deep/nested/new/location" "Nested destination should exist" || return 1
    assert_exists "$TEST_DIR/deep/nested/new/location/README.md" "Files should be moved" || return 1
}

test_parents_flag_not_set() {
    # Create source project
    create_mock_project "$TEST_DIR/no-parents-source"

    # Move to non-existent nested path WITHOUT -p should fail
    assert_fails "Should fail without -p flag" \
        "$SCRIPT" "$TEST_DIR/no-parents-source" "$TEST_DIR/nonexistent/deep/path" -f
}

test_verify_healthy() {
    # Create a healthy project
    create_mock_project "$TEST_DIR/healthy-project"

    local output
    output=$("$SCRIPT" --verify 2>&1)

    if echo "$output" | grep -q "All checks passed"; then
        return 0
    else
        echo "  Expected all checks to pass"
        echo "  Output: $output"
        return 1
    fi
}

test_verify_broken() {
    # Create project then delete it
    create_mock_project "$TEST_DIR/verify-broken"
    rm -rf "$TEST_DIR/verify-broken"

    local output
    output=$("$SCRIPT" --verify 2>&1)

    if echo "$output" | grep -q "broken history reference"; then
        return 0
    else
        echo "  Expected broken history reference"
        echo "  Output: $output"
        return 1
    fi
}

test_info_basic() {
    # Create a project
    create_mock_project "$TEST_DIR/info-project"

    local output
    output=$("$SCRIPT" --info "$TEST_DIR/info-project" 2>&1)

    # Should show path and session info
    if echo "$output" | grep -q "info-project" && echo "$output" | grep -q "Sessions:"; then
        return 0
    else
        echo "  Expected project info with sessions"
        echo "  Output: $output"
        return 1
    fi
}

test_fix_explicit() {
    # Create project, simulate manual mv
    create_mock_project "$TEST_DIR/fix-before"
    local old_abs
    old_abs=$(cd "$TEST_DIR/fix-before" && pwd)

    # Manual mv (breaking history)
    mv "$TEST_DIR/fix-before" "$TEST_DIR/fix-after"

    # Run fix with --from/--to
    "$SCRIPT" --fix --from "$old_abs" --to "$TEST_DIR/fix-after" -f

    # Verify history.jsonl was updated
    local new_abs
    new_abs=$(cd "$TEST_DIR/fix-after" && pwd)
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$new_abs" "History should point to new path" || return 1
    assert_not_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$old_abs" "History should not contain old path" || return 1

    # Verify session folder was renamed
    local old_encoded="${old_abs//\//-}"
    local new_encoded="${new_abs//\//-}"
    assert_not_exists "$MOCK_CLAUDE_DIR/projects/$old_encoded" "Old session folder should be gone" || return 1
    assert_dir_exists "$MOCK_CLAUDE_DIR/projects/$new_encoded" "New session folder should exist" || return 1
}

test_fix_auto_detect() {
    # Create project with a known name, simulate manual mv
    create_mock_project "$TEST_DIR/auto-project"
    local old_abs
    old_abs=$(cd "$TEST_DIR/auto-project" && pwd)

    # Manual mv to a different location
    mkdir -p "$TEST_DIR/new-home"
    mv "$TEST_DIR/auto-project" "$TEST_DIR/new-home/auto-project"

    local new_abs
    new_abs=$(cd "$TEST_DIR/new-home/auto-project" && pwd)

    # Run fix with just the new path — should auto-detect old
    "$SCRIPT" --fix "$new_abs" -f

    # Verify history was updated
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$new_abs" "History should point to new path" || return 1
    assert_not_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$old_abs" "History should not contain old path" || return 1
}

test_fix_nothing_broken() {
    # Create healthy project
    create_mock_project "$TEST_DIR/all-good"

    local output
    output=$("$SCRIPT" --fix -f 2>&1)

    if echo "$output" | grep -q "No broken references found"; then
        return 0
    else
        echo "  Expected 'No broken references found'"
        echo "  Output: $output"
        return 1
    fi
}

# ============================================================================
# PRUNE TESTS
# ============================================================================

test_prune_orphaned() {
    # Create a real project (so history has entries)
    create_mock_project "$TEST_DIR/real-project"

    # Create an orphaned session folder (not referenced in history.jsonl)
    mkdir -p "$MOCK_CLAUDE_DIR/projects/-orphaned-session-folder"
    echo '{"type":"session","data":"orphaned"}' > "$MOCK_CLAUDE_DIR/projects/-orphaned-session-folder/session1.jsonl"

    # Run prune
    local output
    output=$("$SCRIPT" --prune -f 2>&1)

    # Orphaned folder should be removed
    assert_not_exists "$MOCK_CLAUDE_DIR/projects/-orphaned-session-folder" "Orphaned session should be removed" || return 1

    # Real project session folder should still exist
    local real_abs
    real_abs=$(cd "$TEST_DIR/real-project" && pwd)
    local real_encoded="${real_abs//\//-}"
    assert_dir_exists "$MOCK_CLAUDE_DIR/projects/$real_encoded" "Real project session should remain" || return 1

    # Output should mention pruning
    if echo "$output" | grep -q "Pruned"; then
        return 0
    else
        echo "  Expected 'Pruned' in output"
        echo "  Output: $output"
        return 1
    fi
}

test_prune_nothing() {
    # Create a healthy project (no orphans)
    create_mock_project "$TEST_DIR/healthy-project"

    local output
    output=$("$SCRIPT" --prune 2>&1)

    if echo "$output" | grep -q "No orphaned session folders found"; then
        return 0
    else
        echo "  Expected 'No orphaned session folders found'"
        echo "  Output: $output"
        return 1
    fi
}

test_prune_dry_run() {
    # Create a real project
    create_mock_project "$TEST_DIR/real-project"

    # Create an orphaned session folder
    mkdir -p "$MOCK_CLAUDE_DIR/projects/-orphaned-dry-run"
    echo '{"type":"session"}' > "$MOCK_CLAUDE_DIR/projects/-orphaned-dry-run/session1.jsonl"

    # Run prune with --dry-run
    local output
    output=$("$SCRIPT" --prune --dry-run 2>&1)

    # Orphaned folder should still exist
    assert_dir_exists "$MOCK_CLAUDE_DIR/projects/-orphaned-dry-run" "Orphaned session should NOT be removed in dry-run" || return 1

    # Output should indicate dry-run
    if echo "$output" | grep -q "Would remove"; then
        return 0
    else
        echo "  Expected 'Would remove' in output"
        echo "  Output: $output"
        return 1
    fi
}

# ============================================================================
# CASE-SENSITIVITY TESTS
# ============================================================================

test_case_insensitive_path() {
    # Skip on case-sensitive filesystems
    local testdir="$TEST_DIR/CaSeTest"
    mkdir -p "$testdir"
    if ! ls "$TEST_DIR/casetest" &>/dev/null 2>&1; then
        log_skip "Filesystem is case-sensitive, skipping"
        return 0
    fi
    rm -rf "$testdir"

    # Create project with lowercase path
    mkdir -p "$TEST_DIR/projects/myapp"
    create_mock_project "$TEST_DIR/projects/myapp"
    local source_abs
    source_abs=$(cd "$TEST_DIR/projects/myapp" && pwd)

    # Overwrite history.jsonl with canonical (lowercase) path
    # (simulating what Claude Code stores)
    echo "{\"project\":\"$source_abs\",\"session\":\"s1\"}" > "$MOCK_CLAUDE_DIR/history.jsonl"

    # Run clamp using UPPERCASE path (simulating user's shell casing)
    # On case-insensitive FS, this resolves to the same directory
    local upper_source="$TEST_DIR/PROJECTS/myapp"

    "$SCRIPT" "$upper_source" "$TEST_DIR/newloc/myapp" -f -p

    # Verify history was updated (the critical assertion)
    assert_not_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$source_abs" \
        "Old path should not be in history" || return 1
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$TEST_DIR/newloc/myapp" \
        "New path should be in history" || return 1
}

# ============================================================================
# WINDOWS PATH HANDLING - HELPER TESTS
# ============================================================================

test_encode_path_posix_basic() {
    PATH_ENCODING="posix"
    assert_eq "$(encode_path /home/me/foo)" "-home-me-foo"
}

test_encode_path_windows_git_bash_form() {
    PATH_ENCODING="windows"
    assert_eq "$(encode_path /d/projects/foo)" "D--projects-foo"
}

test_encode_path_windows_forward_slash() {
    PATH_ENCODING="windows"
    assert_eq "$(encode_path D:/projects/foo)" "D--projects-foo"
}

test_encode_path_windows_backslash() {
    PATH_ENCODING="windows"
    assert_eq "$(encode_path 'D:\projects\foo')" "D--projects-foo"
}

test_encode_path_windows_lowercase_drive() {
    PATH_ENCODING="windows"
    assert_eq "$(encode_path /c/users/me)" "C--users-me"
}

test_encode_path_windows_deep_multi_segment() {
    PATH_ENCODING="windows"
    assert_eq "$(encode_path /d/dev/example/some-deep-project)" \
        "D--dev-example-some-deep-project"
}

test_encode_path_hyphen_collision_documented() {
    # Lossy encoding: different paths can produce the same encoded form.
    PATH_ENCODING="windows"
    local a b
    a=$(encode_path 'D:/my-cool-project')
    b=$(encode_path 'D:/my/cool/project')
    assert_eq "$a" "$b" "Both paths should encode identically (documented collision)"
}

test_to_history_form_posix_identity() {
    PATH_ENCODING="posix"
    assert_eq "$(to_history_form /home/me/foo)" "/home/me/foo"
}

test_to_history_form_windows() {
    PATH_ENCODING="windows"
    assert_eq "$(to_history_form 'D:/projects/foo')" 'D:\\projects\\foo'
}

test_to_history_form_windows_byte_exact() {
    # Verify byte-for-byte that to_history_form produces 2 backslash bytes per separator.
    PATH_ENCODING="windows"
    local got_hex
    got_hex=$(printf '%s' "$(to_history_form 'D:/projects/foo')" | xxd -p)
    # Expected: D:\\projects\\foo as raw bytes — 5c5c per separator
    assert_eq "$got_hex" "443a5c5c70726f6a656374735c5c666f6f"
}

test_from_history_form_posix_identity() {
    PATH_ENCODING="posix"
    assert_eq "$(from_history_form /home/me/foo)" "/home/me/foo"
}

test_from_history_form_windows() {
    PATH_ENCODING="windows"
    assert_eq "$(from_history_form 'D:\\projects\\foo')" "D:/projects/foo"
}

test_from_history_form_windows_byte_exact() {
    PATH_ENCODING="windows"
    local got_hex
    got_hex=$(printf '%s' "$(from_history_form 'D:\\projects\\foo')" | xxd -p)
    # Expected: D:/projects/foo as raw bytes — 2f per separator
    assert_eq "$got_hex" "443a2f70726f6a656374732f666f6f"
}

test_to_from_roundtrip_basic() {
    PATH_ENCODING="windows"
    local sample="D:/projects/foo"
    assert_eq "$(from_history_form "$(to_history_form "$sample")")" "$sample"
}

test_to_from_roundtrip_non_ascii() {
    PATH_ENCODING="windows"
    local sample='D:/Документы/foo'
    assert_eq "$(from_history_form "$(to_history_form "$sample")")" "$sample"
}

test_to_from_roundtrip_with_spaces() {
    PATH_ENCODING="windows"
    local sample='D:/My Projects/cool app'
    assert_eq "$(from_history_form "$(to_history_form "$sample")")" "$sample"
}

test_to_from_roundtrip_with_parens() {
    PATH_ENCODING="windows"
    local sample='D:/foo (copy)/bar'
    assert_eq "$(from_history_form "$(to_history_form "$sample")")" "$sample"
}

test_is_absolute_path_posix_relative_rejected() {
    PATH_ENCODING="posix"
    if is_absolute_path "rel/path"; then
        echo "  rel/path should not be absolute"
        return 1
    fi
}

test_is_absolute_path_windows_forms_accepted() {
    PATH_ENCODING="windows"
    is_absolute_path "D:/foo"   || { echo "  D:/foo should be absolute"; return 1; }
    is_absolute_path 'D:\foo'   || { echo "  D:\\foo should be absolute"; return 1; }
    is_absolute_path "/d/foo"   || { echo "  /d/foo should be absolute"; return 1; }
}

test_encode_path_unc_documented() {
    # UNC handling is out of scope; encoded form indistinguishable.
    # Test pins this behavior as baseline for improvement.
    PATH_ENCODING="windows"
    local back fwd
    back=$(encode_path '\\server\share\foo')
    fwd=$(encode_path '//server/share/foo')
    assert_eq "$back" "--server-share-foo"
    assert_eq "$fwd"  "--server-share-foo"
}

# ============================================================================
# WINDOWS MODE - INTEGRATION TESTS
# ============================================================================

test_win_list_with_real_projects() {
    create_mock_windows_project "$TEST_DIR/proj-a"
    create_mock_windows_project "$TEST_DIR/proj-b"

    PATH_ENCODING="windows"
    local proj_a_win proj_b_win
    proj_a_win=$(get_absolute_path "$TEST_DIR/proj-a")
    proj_b_win=$(get_absolute_path "$TEST_DIR/proj-b")

    local output
    output=$("$SCRIPT" --encoding windows --list 2>&1)

    if ! echo "$output" | grep -qF -- "$proj_a_win"; then
        echo "  Expected proj-a in Windows form in output"
        echo "  Output: $output"
        return 1
    fi
    if ! echo "$output" | grep -qF -- "$proj_b_win"; then
        echo "  Expected proj-b in Windows form in output"
        echo "  Output: $output"
        return 1
    fi
    # User-facing output should be in filesystem form, not history form.
    if echo "$output" | grep -qE '\\\\'; then
        echo "  Output should not contain double-backslash JSON-escape form"
        echo "  Output: $output"
        return 1
    fi
}

test_win_verify_broken() {
    create_mock_windows_project "$TEST_DIR/broken-proj"

    PATH_ENCODING="windows"
    local proj_win
    proj_win=$(get_absolute_path "$TEST_DIR/broken-proj")

    rm -rf "$TEST_DIR/broken-proj"

    local output
    output=$("$SCRIPT" --encoding windows --verify 2>&1)

    if ! echo "$output" | grep -qF -- "$proj_win"; then
        echo "  Expected broken path (Windows form) in verify output"
        echo "  Output: $output"
        return 1
    fi
    if echo "$output" | grep -qE '\\\\'; then
        echo "  Output should not contain double-backslash JSON-escape form"
        echo "  Output: $output"
        return 1
    fi
}

test_win_move_basic() {
    create_mock_windows_project "$TEST_DIR/source-proj"

    PATH_ENCODING="windows"
    local source_win dest_win source_encoded dest_encoded
    source_win=$(get_absolute_path "$TEST_DIR/source-proj")
    dest_win=$(get_absolute_path "$TEST_DIR/dest-proj")
    source_encoded=$(encode_path "$source_win")
    dest_encoded=$(encode_path "$dest_win")

    "$SCRIPT" --encoding windows "$source_win" "$dest_win" -f

    assert_not_exists "$TEST_DIR/source-proj"           "Source folder should be gone" || return 1
    assert_dir_exists "$TEST_DIR/dest-proj"             "Destination folder should exist" || return 1
    assert_not_exists "$MOCK_CLAUDE_DIR/projects/$source_encoded" \
        "Old encoded session folder should be gone" || return 1
    assert_dir_exists "$MOCK_CLAUDE_DIR/projects/$dest_encoded" \
        "New encoded session folder should exist" || return 1

    local source_hist dest_hist
    source_hist=$(to_history_form "$source_win")
    dest_hist=$(to_history_form "$dest_win")
    assert_not_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$source_hist" \
        "History should not contain old path" || return 1
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$dest_hist" \
        "History should contain new path" || return 1

    # Session JSONL's embedded path reference should be updated too.
    local jsonl="$MOCK_CLAUDE_DIR/projects/$dest_encoded/session1.jsonl"
    assert_contains "$jsonl" "$dest_hist" \
        "Session JSONL should contain new path" || return 1
    assert_not_contains "$jsonl" "$source_hist" \
        "Session JSONL should not contain old path" || return 1
}

test_win_fix_explicit() {
    create_mock_windows_project "$TEST_DIR/old-loc"

    PATH_ENCODING="windows"
    local old_win
    old_win=$(get_absolute_path "$TEST_DIR/old-loc")

    # Move project outside of clamp (history.jsonl will reference missing path).
    mkdir -p "$TEST_DIR/new-loc"
    cp -R "$TEST_DIR/old-loc/." "$TEST_DIR/new-loc/"
    rm -rf "$TEST_DIR/old-loc"

    local new_win old_encoded new_encoded
    new_win=$(get_absolute_path "$TEST_DIR/new-loc")
    old_encoded=$(encode_path "$old_win")
    new_encoded=$(encode_path "$new_win")

    "$SCRIPT" --encoding windows --fix --from "$old_win" --to "$new_win" -f

    assert_not_exists "$MOCK_CLAUDE_DIR/projects/$old_encoded" || return 1
    assert_dir_exists "$MOCK_CLAUDE_DIR/projects/$new_encoded" || return 1

    local new_hist old_hist
    new_hist=$(to_history_form "$new_win")
    old_hist=$(to_history_form "$old_win")
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$new_hist" || return 1
    assert_not_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$old_hist" || return 1

    local jsonl="$MOCK_CLAUDE_DIR/projects/$new_encoded/session1.jsonl"
    assert_contains "$jsonl" "$new_hist" \
        "Session JSONL should contain new path" || return 1
}

test_win_fix_auto_find_no_posix_leak() {
    create_mock_windows_project "$TEST_DIR/auto-proj"

    PATH_ENCODING="windows"
    local old_win
    old_win=$(get_absolute_path "$TEST_DIR/auto-proj")

    # Manual mv to a location find can discover (under $HOME = $TEST_DIR)
    mkdir -p "$TEST_DIR/new-home"
    mv "$TEST_DIR/auto-proj" "$TEST_DIR/new-home/auto-proj"

    local new_win
    new_win=$(get_absolute_path "$TEST_DIR/new-home/auto-proj")

    "$SCRIPT" --encoding windows --fix -f

    local new_hist
    new_hist=$(to_history_form "$new_win")
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$new_hist" \
        "History should contain new Windows-form path after auto-fix" || return 1

    # Regression check: no POSIX-mounted /c/... leak in history.jsonl.
    if grep -qE '"project":"/[a-z]/' "$MOCK_CLAUDE_DIR/history.jsonl"; then
        echo "  history.jsonl contains a POSIX-mounted-form path"
        echo "  Indicates cd && pwd POSIX-form leak regression"
        cat "$MOCK_CLAUDE_DIR/history.jsonl"
        return 1
    fi
}

test_win_move_with_spaces() {
    create_mock_windows_project "$TEST_DIR/my proj"

    PATH_ENCODING="windows"
    local source_win dest_win dest_encoded
    source_win=$(get_absolute_path "$TEST_DIR/my proj")
    dest_win=$(get_absolute_path "$TEST_DIR/new proj")
    dest_encoded=$(encode_path "$dest_win")

    "$SCRIPT" --encoding windows "$source_win" "$dest_win" -f

    assert_not_exists "$TEST_DIR/my proj"           "Source with space should be gone" || return 1
    assert_dir_exists "$TEST_DIR/new proj"          "Destination with space should exist" || return 1
    assert_dir_exists "$MOCK_CLAUDE_DIR/projects/$dest_encoded" \
        "New encoded session folder should exist" || return 1

    local dest_hist
    dest_hist=$(to_history_form "$dest_win")
    assert_contains "$MOCK_CLAUDE_DIR/history.jsonl" "$dest_hist" \
        "History should contain new Windows-form path (with spaces)" || return 1
}

test_encoding_flag_validation() {
    if ! "$SCRIPT" --encoding posix --list > /dev/null 2>&1; then
        echo "  --encoding posix should be accepted"
        return 1
    fi
    if ! "$SCRIPT" --encoding windows --list > /dev/null 2>&1; then
        echo "  --encoding windows should be accepted"
        return 1
    fi
    assert_fails "Invalid --encoding value should be rejected" \
        "$SCRIPT" --encoding invalid --list || return 1
    assert_fails "--encoding with no argument should be rejected" \
        "$SCRIPT" --encoding || return 1
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    echo "clamp Test Suite"
    echo "==============================="
    echo ""

    # Check script exists
    if [[ ! -x "$SCRIPT" ]]; then
        echo "Error: Script not found or not executable: $SCRIPT"
        exit 1
    fi

    # List of all tests
    local all_tests=(
        test_basic_move
        test_relative_source
        test_relative_dest
        test_dest_is_directory
        test_special_chars_brackets
        test_special_chars_spaces
        test_special_chars_dots
        test_symlink_source
        test_dry_run
        test_nonexistent_source
        test_dest_exists
        test_dest_file_exists
        test_missing_parent
        test_no_history
        test_verbose_output
        test_backup_created
        test_no_backup_flag
        test_same_source_dest
        # v1.2.0 tests
        test_list_basic
        test_list_json
        test_list_empty
        test_list_broken_project
        test_here_mode
        test_parents_flag
        test_parents_flag_not_set
        test_verify_healthy
        test_verify_broken
        test_info_basic
        test_fix_explicit
        test_fix_auto_detect
        test_fix_nothing_broken
        # prune tests
        test_prune_orphaned
        test_prune_nothing
        test_prune_dry_run
        # case-sensitivity tests
        test_case_insensitive_path
        # Windows path handling — helper tests
        test_encode_path_posix_basic
        test_encode_path_windows_git_bash_form
        test_encode_path_windows_forward_slash
        test_encode_path_windows_backslash
        test_encode_path_windows_lowercase_drive
        test_encode_path_windows_deep_multi_segment
        test_encode_path_hyphen_collision_documented
        test_to_history_form_posix_identity
        test_to_history_form_windows
        test_to_history_form_windows_byte_exact
        test_from_history_form_posix_identity
        test_from_history_form_windows
        test_from_history_form_windows_byte_exact
        test_to_from_roundtrip_basic
        test_to_from_roundtrip_non_ascii
        test_to_from_roundtrip_with_spaces
        test_to_from_roundtrip_with_parens
        test_is_absolute_path_posix_relative_rejected
        test_is_absolute_path_windows_forms_accepted
        test_encode_path_unc_documented
        # Windows mode — integration tests
        test_win_list_with_real_projects
        test_win_verify_broken
        test_win_move_basic
        test_win_fix_explicit
        test_win_fix_auto_find_no_posix_leak
        test_win_move_with_spaces
        test_encoding_flag_validation
    )

    # Run specific test or all tests
    if [[ $# -ge 1 ]]; then
        # Run specific test
        local test_name="$1"
        if declare -f "$test_name" > /dev/null; then
            run_test "$test_name"
        else
            echo "Error: Unknown test: $test_name"
            echo "Available tests:"
            for t in "${all_tests[@]}"; do
                echo "  $t"
            done
            exit 1
        fi
    else
        # Run all tests
        for test in "${all_tests[@]}"; do
            run_test "$test" || true
        done
    fi

    # Summary
    echo ""
    echo "==============================="
    echo "Results:"
    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"

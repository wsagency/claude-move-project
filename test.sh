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
    TEST_DIR=$(mktemp -d)
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
# CLAUDE_CONFIG_DIR TESTS
# ============================================================================

test_claude_config_dir_move() {
    # Set up a custom config dir (not under $HOME/.claude)
    local custom_config="$TEST_DIR/custom-config"
    mkdir -p "$custom_config/projects"
    touch "$custom_config/history.jsonl"

    # Remove the default $HOME/.claude so we can verify it's not used
    rm -rf "$MOCK_CLAUDE_DIR"

    # Create source project and its session data in custom config dir
    local source_abs="$TEST_DIR/source-project"
    mkdir -p "$source_abs/.claude"
    echo "# Test" > "$source_abs/README.md"

    local encoded="${source_abs//\//-}"
    mkdir -p "$custom_config/projects/$encoded"
    echo "{\"type\":\"session\",\"cwd\":\"$source_abs\"}" > "$custom_config/projects/$encoded/session1.jsonl"
    echo "{\"project\":\"$source_abs\",\"session\":\"session1\"}" >> "$custom_config/history.jsonl"

    local dest_abs="$TEST_DIR/dest-project"

    # Run with CLAUDE_CONFIG_DIR
    CLAUDE_CONFIG_DIR="$custom_config" "$SCRIPT" "$source_abs" "$dest_abs" -f

    # Verify project moved
    assert_not_exists "$source_abs" "Source should be gone" || return 1
    assert_dir_exists "$dest_abs" "Destination should exist" || return 1

    # Verify session folder renamed in custom config dir
    local new_encoded="${dest_abs//\//-}"
    assert_not_exists "$custom_config/projects/$encoded" "Old session folder should be gone" || return 1
    assert_dir_exists "$custom_config/projects/$new_encoded" "New session folder should exist in custom config" || return 1

    # Verify history.jsonl updated in custom config dir
    assert_not_contains "$custom_config/history.jsonl" "$source_abs" "Old path should not be in history" || return 1
    assert_contains "$custom_config/history.jsonl" "$dest_abs" "New path should be in history" || return 1

    # Verify cwd rewritten inside session JSONL
    assert_not_contains "$custom_config/projects/$new_encoded/session1.jsonl" "$source_abs" "Old cwd should not be in session file" || return 1
    assert_contains "$custom_config/projects/$new_encoded/session1.jsonl" "$dest_abs" "New cwd should be in session file" || return 1

    # Verify default $HOME/.claude was NOT created
    assert_not_exists "$MOCK_CLAUDE_DIR" "Default ~/.claude should not be created" || return 1
}

test_claude_config_dir_list() {
    # Set up a custom config dir
    local custom_config="$TEST_DIR/custom-config"
    mkdir -p "$custom_config/projects"
    touch "$custom_config/history.jsonl"

    # Remove the default $HOME/.claude
    rm -rf "$MOCK_CLAUDE_DIR"

    # Create a project entry in custom config
    local project_abs="$TEST_DIR/listed-project"
    mkdir -p "$project_abs"
    echo "{\"project\":\"$project_abs\",\"session\":\"s1\"}" >> "$custom_config/history.jsonl"

    local output
    output=$(CLAUDE_CONFIG_DIR="$custom_config" "$SCRIPT" --list 2>&1)

    if echo "$output" | grep -q "listed-project"; then
        return 0
    else
        echo "  Expected project in --list output"
        echo "  Output: $output"
        return 1
    fi
}

test_claude_config_dir_fix() {
    # Set up a custom config dir
    local custom_config="$TEST_DIR/custom-config"
    mkdir -p "$custom_config/projects"
    touch "$custom_config/history.jsonl"

    # Remove the default $HOME/.claude
    rm -rf "$MOCK_CLAUDE_DIR"

    # Create project, simulate manual mv
    local old_abs="$TEST_DIR/fix-old"
    mkdir -p "$old_abs/.claude"
    echo "# Test" > "$old_abs/README.md"

    local old_encoded="${old_abs//\//-}"
    mkdir -p "$custom_config/projects/$old_encoded"
    echo "{\"type\":\"session\",\"cwd\":\"$old_abs\"}" > "$custom_config/projects/$old_encoded/session1.jsonl"
    echo "{\"project\":\"$old_abs\",\"session\":\"s1\"}" >> "$custom_config/history.jsonl"

    # Manual mv
    mv "$old_abs" "$TEST_DIR/fix-new"
    local new_abs="$TEST_DIR/fix-new"

    # Run fix with CLAUDE_CONFIG_DIR
    CLAUDE_CONFIG_DIR="$custom_config" "$SCRIPT" --fix --from "$old_abs" --to "$new_abs" -f

    # Verify session folder renamed
    local new_encoded="${new_abs//\//-}"
    assert_not_exists "$custom_config/projects/$old_encoded" "Old session folder should be gone" || return 1
    assert_dir_exists "$custom_config/projects/$new_encoded" "New session folder should exist" || return 1

    # Verify history updated
    assert_contains "$custom_config/history.jsonl" "$new_abs" "History should have new path" || return 1
    assert_not_contains "$custom_config/history.jsonl" "$old_abs" "History should not have old path" || return 1

    # Verify cwd rewritten in session file
    assert_contains "$custom_config/projects/$new_encoded/session1.jsonl" "$new_abs" "Session file should have new cwd" || return 1
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
        # CLAUDE_CONFIG_DIR tests
        test_claude_config_dir_move
        test_claude_config_dir_list
        test_claude_config_dir_fix
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

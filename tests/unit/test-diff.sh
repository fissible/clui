#!/usr/bin/env bash
# tests/unit/test-diff.sh — Unit tests for src/diff.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/diff.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── Helper: create a minimal unified diff ────────────────────────────────────

_make_diff() {
    cat <<'DIFF'
diff --git a/foo.sh b/foo.sh
index abc123..def456 100644
--- a/foo.sh
+++ b/foo.sh
@@ -1,5 +1,6 @@
 line one
 line two
-old line three
+new line three
+added line four
 line five
 line six
DIFF
}

_make_multi_file_diff() {
    cat <<'DIFF'
diff --git a/alpha.sh b/alpha.sh
index aaa..bbb 100644
--- a/alpha.sh
+++ b/alpha.sh
@@ -1,3 +1,3 @@
 same
-removed
+added
 same
diff --git a/beta.sh b/beta.sh
new file mode 100644
--- /dev/null
+++ b/beta.sh
@@ -0,0 +1,2 @@
+brand new file
+second line
DIFF
}

# ── shellframe_diff_parse ────────────────────────────────────────────────────

ptyunit_test_begin "diff_parse: populates row count"
shellframe_diff_parse <<< "$(_make_diff)"
assert_eq "7" "$SHELLFRAME_DIFF_ROW_COUNT" "1 hdr + 2 ctx + 1 chg + 1 add + 2 ctx = 7 rows"

ptyunit_test_begin "diff_parse: first row is hdr"
assert_eq "hdr" "${SHELLFRAME_DIFF_TYPES[0]}"

ptyunit_test_begin "diff_parse: hdr row has filename on both sides"
assert_eq "foo.sh" "${SHELLFRAME_DIFF_LEFT[0]}"
assert_eq "foo.sh" "${SHELLFRAME_DIFF_RIGHT[0]}"

ptyunit_test_begin "diff_parse: context line has same text on both sides"
assert_eq "ctx" "${SHELLFRAME_DIFF_TYPES[1]}"
assert_eq "line one" "${SHELLFRAME_DIFF_LEFT[1]}"
assert_eq "line one" "${SHELLFRAME_DIFF_RIGHT[1]}"

ptyunit_test_begin "diff_parse: context line has line numbers on both sides"
assert_eq "1" "${SHELLFRAME_DIFF_LNUMS[1]}"
assert_eq "1" "${SHELLFRAME_DIFF_RNUMS[1]}"

ptyunit_test_begin "diff_parse: paired del+add becomes chg"
assert_eq "chg" "${SHELLFRAME_DIFF_TYPES[3]}"
assert_eq "old line three" "${SHELLFRAME_DIFF_LEFT[3]}"
assert_eq "new line three" "${SHELLFRAME_DIFF_RIGHT[3]}"

ptyunit_test_begin "diff_parse: unpaired add is type add"
assert_eq "add" "${SHELLFRAME_DIFF_TYPES[4]}"
assert_eq "" "${SHELLFRAME_DIFF_LEFT[4]}" "left is empty for add"
assert_eq "added line four" "${SHELLFRAME_DIFF_RIGHT[4]}"

ptyunit_test_begin "diff_parse: line numbers track correctly after changes"
assert_eq "3" "${SHELLFRAME_DIFF_LNUMS[3]}" "del line 3"
assert_eq "3" "${SHELLFRAME_DIFF_RNUMS[3]}" "add line 3"
assert_eq "4" "${SHELLFRAME_DIFF_RNUMS[4]}" "add line 4"

# ── File index ───────────────────────────────────────────────────────────────

ptyunit_test_begin "diff_parse: FILES array has filename"
assert_eq "1" "${#SHELLFRAME_DIFF_FILES[@]}"
assert_eq "foo.sh" "${SHELLFRAME_DIFF_FILES[0]}"

ptyunit_test_begin "diff_parse: FILE_ROWS points to hdr row"
assert_eq "0" "${SHELLFRAME_DIFF_FILE_ROWS[0]}"

# ── Multi-file diff ─────────────────────────────────────────────────────────

ptyunit_test_begin "diff_parse: multi-file detects 2 files"
shellframe_diff_parse <<< "$(_make_multi_file_diff)"
assert_eq "2" "${#SHELLFRAME_DIFF_FILES[@]}"
assert_eq "alpha.sh" "${SHELLFRAME_DIFF_FILES[0]}"
assert_eq "beta.sh" "${SHELLFRAME_DIFF_FILES[1]}"

ptyunit_test_begin "diff_parse: file_sep between files"
_found_sep=0
_i=0
for (( _i=0; _i < SHELLFRAME_DIFF_ROW_COUNT; _i++ )); do
    [[ "${SHELLFRAME_DIFF_TYPES[$_i]}" == "file_sep" ]] && _found_sep=1
done
assert_eq "1" "$_found_sep" "should have a file_sep row"

ptyunit_test_begin "diff_parse: new file detected as added"
assert_eq "modified" "${SHELLFRAME_DIFF_FILE_STATUS[0]}" "alpha.sh"
assert_eq "added" "${SHELLFRAME_DIFF_FILE_STATUS[1]}" "beta.sh"

# ── shellframe_diff_clear ────────────────────────────────────────────────────

ptyunit_test_begin "diff_clear: resets all arrays"
shellframe_diff_parse <<< "$(_make_diff)"
shellframe_diff_clear
assert_eq "0" "$SHELLFRAME_DIFF_ROW_COUNT"
assert_eq "0" "${#SHELLFRAME_DIFF_TYPES[@]}"
assert_eq "0" "${#SHELLFRAME_DIFF_FILES[@]}"

# ── shellframe_diff_parse_string ─────────────────────────────────────────────

ptyunit_test_begin "diff_parse_string: works from variable"
_diff_text=""
_diff_text=$(_make_diff)
shellframe_diff_parse_string "$_diff_text"
assert_eq "7" "$SHELLFRAME_DIFF_ROW_COUNT"

# ── Summary ──────────────────────────────────────────────────────────────────

ptyunit_test_summary

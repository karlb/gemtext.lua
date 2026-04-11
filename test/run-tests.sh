#!/usr/bin/env bash
# Test runner for gemtext.lua fixtures.
#
# Each *.test file is a series of test cases. A test case looks like:
#
#     Optional description lines before the fence.
#     ```
#     djot input
#     .
#     expected gemtext
#     ```
#
# (The fence can be 3+ backticks; the closing fence must have the same
#  count as the opening, so content containing ``` can use ```` etc.)
#
# For each case we run `pandoc -f djot --to ../gemtext.lua` on the input
# and diff stdout against the expected block.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WRITER="$SCRIPT_DIR/../gemtext.lua"

if ! command -v pandoc >/dev/null 2>&1; then
  echo "error: pandoc not found on PATH" >&2
  exit 2
fi
if [[ ! -f $WRITER ]]; then
  echo "error: writer not found at $WRITER" >&2
  exit 2
fi

total=0
failed=0

red() { printf '\033[31m%s\033[0m' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }

run_case() {
  local file=$1
  local linenum=$2
  local desc=$3
  local input=$4
  local expected=$5

  total=$((total + 1))
  # First non-blank line of the preamble is the human-readable label.
  local label
  label=$(printf '%s' "$desc" | awk 'NF{print; exit}' | cut -c1-60)
  [[ -z $label ]] && label="(case at line $linenum)"

  # Command substitution strips trailing newlines, so append a sentinel
  # and strip it afterwards — gemtext output is newline-sensitive.
  local actual
  actual=$(printf '%s' "$input" | pandoc -f djot --to "$WRITER" 2>/dev/null; printf x) || true
  actual=${actual%x}

  if [[ $actual == "$expected" ]]; then
    printf '  %s %s\n' "$(green PASS)" "$label"
  else
    failed=$((failed + 1))
    printf '  %s %s (line %d)\n' "$(red FAIL)" "$label" "$linenum"
    diff -u <(printf '%s' "$expected") <(printf '%s' "$actual") \
      | sed 's/^/    /'
  fi
}

parse_file() {
  local file=$1
  local state=preamble
  local desc="" input="" expected=""
  local fence=""
  local linenum=0
  local case_line=0
  local open_re='^(`+)'

  while IFS= read -r line || [[ -n $line ]]; do
    linenum=$((linenum + 1))
    case $state in
      preamble)
        if [[ $line =~ $open_re ]]; then
          fence=${BASH_REMATCH[1]}
          state=input
          case_line=$linenum
        else
          desc="${desc}${line}"$'\n'
        fi
        ;;
      input)
        if [[ $line == "." ]]; then
          state=expected
        else
          input="${input}${line}"$'\n'
        fi
        ;;
      expected)
        if [[ $line == "$fence" ]]; then
          run_case "$file" "$case_line" "$desc" "$input" "$expected"
          desc=""
          input=""
          expected=""
          state=preamble
        else
          expected="${expected}${line}"$'\n'
        fi
        ;;
    esac
  done < "$file"
}

shopt -s nullglob
files=("$SCRIPT_DIR"/*.test)
if ((${#files[@]} == 0)); then
  echo "no .test files found in $SCRIPT_DIR" >&2
  exit 2
fi

for file in "${files[@]}"; do
  printf '\n== %s ==\n' "$(basename "$file")"
  parse_file "$file"
done

printf '\n%d passed, %d failed, %d total\n' \
  $((total - failed)) "$failed" "$total"

[[ $failed -eq 0 ]]

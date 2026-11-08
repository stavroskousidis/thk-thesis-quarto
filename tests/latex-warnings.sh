#!/usr/bin/env bash
# List LaTeX warnings and overfull/underfull boxes of the last render with
# `latex-clean: false` (see `make warnings`). For each box, the matching lines
# of the generated .tex file are shown, so you can find the place in your .qmd.
# Exit code: number of findings (0 = clean), capped at 99.
#   tests/latex-warnings.sh [file.log] [file.tex]
LOG="${1:-$(ls -t ./*.log 2>/dev/null | head -1)}"
TEX="${2:-thesis.tex}"
[ -f "$LOG" ] || { echo "No LaTeX log found -- run 'make warnings'."; exit 99; }

n=0
while IFS= read -r line; do
  n=$((n + 1))
  echo "$line"
  if [[ "$line" =~ lines\ ([0-9]+)--([0-9]+) ]] && [ -f "$TEX" ]; then
    sed -n "${BASH_REMATCH[1]},${BASH_REMATCH[2]}p" "$TEX" | cut -c1-110 | sed 's/^/      | /' | head -6
  fi
done < <(grep -E '^(Overfull|Underfull) \\[hv]box|^(LaTeX|Package|Class) [^ ]+ Warning|^LaTeX Warning|Missing character' "$LOG" \
         | sed 's/ detected at line.*//')

if [ "$n" -eq 0 ]; then echo "No LaTeX warnings, no overfull or underfull boxes."; fi
[ "$n" -gt 99 ] && n=99
exit "$n"

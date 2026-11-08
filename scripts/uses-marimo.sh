#!/usr/bin/env bash
# Exit 0 if any chapter declares `engine: marimo` in its front matter
# (the YAML block at the top of the file), else 1. Used by `make check`.
for f in $(find . -name '*.qmd' -not -path './tests/*' -not -path './_extensions/*' -not -path './_book/*'); do
  awk 'NR==1 && !/^---[[:space:]]*$/ {exit 1}
       /^---[[:space:]]*$/ {n++; if (n==2) exit 1; next}
       n==1 && /^engine:[[:space:]]*marimo/ {found=1; exit 0}
       END {exit !found}' "$f" && exit 0
done
exit 1

#!/usr/bin/env bash
# Smoke tests: render copies of the project with different settings and check
# the generated LaTeX. Usage:
#   tests/smoke.sh minimal   one quick render (no marimo chapter) -- used by `make check`
#   tests/smoke.sh all       all variants (declaration positions, custom
#                            declaration text, invalid settings, zero warnings)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-all}"
QUARTO="${QUARTO:-quarto}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  ok    $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; fail=$((fail + 1)); }

# copy the project without build output, git data and the CryptoBib submodule
copy_project() {
  local dest="$1"
  mkdir -p "$dest"
  (cd "$ROOT" && tar cf - --exclude=./.git --exclude=./_book --exclude=./.quarto \
      --exclude=./_generated --exclude=./bib/cryptobib --exclude=./tests . ) | (cd "$dest" && tar xf -)
  # keep the .tex file for checking
  sed -i.bak 's/^\( *\)keep-tex: false/\1keep-tex: true/' "$dest/_quarto.yml"
  rm -f "$dest/_quarto.yml.bak"
}

# set_yaml <dir> <sed expression>
set_yaml() { sed -i.bak "$2" "$1/_quarto.yml" && rm -f "$1/_quarto.yml.bak"; }

# drop the chapters with marimo cells (fast render without Python)
no_marimo() { set_yaml "$1" '/chapters\/03-layout.qmd/d; /chapters\/04-citations.qmd/d'; }

# render <dir> <log>; returns quarto's exit code
render() { (cd "$1" && "$QUARTO" render >"$2" 2>&1); }

has()    { grep -q -- "$2" "$1/thesis.tex"; }
before() { # before <dir> <a> <b>: first occurrence of a is before first of b
  local a b
  a=$(grep -n -m1 -- "$2" "$1/thesis.tex" | cut -d: -f1)
  b=$(grep -n -m1 -- "$3" "$1/thesis.tex" | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

variant() { echo; echo "== $1"; }

# --- minimal: English defaults, no marimo ------------------------------------
variant "minimal (English, declaration at the end)"
D="$TMP/minimal"; copy_project "$D"; no_marimo "$D"
set_yaml "$D" 's/^\( *\)type: "Bachelor.*/\1type: bachelor/'
if render "$D" "$TMP/minimal.log" && [ -f "$D/_book/thesis.pdf" ]; then
  ok "PDF rendered"
  has "$D" "Submitted by:" && ok "English cover labels" || bad "English cover labels"
  { has "$D" "Bachelor's thesis" && ! has "$D" "Bachelor\\\\textquotesingle"; } \
    && ok "thesis type (typographic apostrophe)" || bad "thesis type (typographic apostrophe)"
  before "$D" "printbibliography" "chapter\*{Declaration}" && ok "declaration after bibliography" \
    || bad "declaration after bibliography"
  before "$D" "tableofcontents" "chapter{Introduction}" && ok "lists before chapter 1" \
    || bad "lists before chapter 1"
else
  bad "PDF rendered (see log below)"; tail -30 "$TMP/minimal.log"
fi

if [ "$MODE" = "minimal" ]; then
  echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit
fi

# --- full template: no LaTeX warnings, no overfull/underfull boxes ------------
# (with the placeholders "Bachelor's or Master's thesis" on the cover)
variant "full template: no LaTeX warnings"
D="$TMP/full"; copy_project "$D"
set_yaml "$D" 's/^\( *\)keep-tex: true/\1keep-tex: true\
\1latex-clean: false/'
if render "$D" "$TMP/full.log"; then
  # numbering: one shared counter for statements, own counters for the rest
  label() { grep -o "\\\\newlabel{$1}{{[^}]*" "$D/index.aux" | sed 's/.*{{//'; }
  [ "$(label def-triangular)" = "3.1" ] && [ "$(label thm-gauss)" = "3.2" ] && \
  [ "$(label lem-consecutive)" = "3.3" ] && [ "$(label rem-legend)" = "3.7" ] \
    && ok "statements share one counter (3.1, 3.2, 3.3, ..., 3.7)" \
    || bad "statements share one counter: def=$(label def-triangular) thm=$(label thm-gauss) rem=$(label rem-legend)"
  [ "$(label eq-gauss)" = "3.1" ] && [ "$(label alg-euclid)" = "3.1" ] \
    && ok "equations and algorithms numbered" || bad "equations and algorithms numbered"
  has "$D" 'Equation~\\eqref{eq-gauss}' && ok 'references: "Equation (3.1)"' || bad 'references: "Equation (3.1)"'
  grep -q 'Euclid' "$D/index.loa" && ok "List of Algorithms" || bad "List of Algorithms"
  if (cd "$D" && "$ROOT/tests/latex-warnings.sh" >"$TMP/full-warnings.txt"); then
    ok "no LaTeX warnings or bad boxes"
  else
    bad "LaTeX warnings or bad boxes:"; sed 's/^/        /' "$TMP/full-warnings.txt"
  fi
else
  bad "PDF rendered"; tail -30 "$TMP/full.log"
fi

# --- pagination as in the TH Köln LaTeX template: abstract on page I ---------
variant "pagination: abstract on page I, chapter 1 on page 1"
D="$TMP/pages"; copy_project "$D"; no_marimo "$D"
set_yaml "$D" 's/^\( *\)keep-tex: true/\1keep-tex: true\
\1latex-clean: false/'
printf '\n\\label{thk-test-abstract}\n' >> "$D/index.qmd"
if render "$D" "$TMP/pages.log"; then
  grep -q '\\newlabel{thk-test-abstract}{{}{I}' "$D/index.aux" && ok "abstract on page I" \
    || bad "abstract on page I: $(grep thk-test-abstract "$D/index.aux")"
  grep -q 'numberline {1}Introduction}{1}' "$D/index.toc" && ok "chapter 1 on page 1" || bad "chapter 1 on page 1"
else
  bad "PDF rendered"; tail -30 "$TMP/pages.log"
fi

# --- without references.qmd the bibliography still precedes appendix and declaration
variant "no references.qmd: bibliography before appendix and declaration"
D="$TMP/norefs"; copy_project "$D"; no_marimo "$D"
set_yaml "$D" '/references.qmd/d'
if render "$D" "$TMP/norefs.log"; then
  before "$D" "printbibliography" "^\\\\appendix" && ok "bibliography before appendix" || bad "bibliography before appendix"
  before "$D" "printbibliography" "chapter\*{Declaration}" && ok "bibliography before declaration" \
    || bad "bibliography before declaration"
else
  bad "PDF rendered"; tail -30 "$TMP/norefs.log"
fi

# --- master's thesis, declaration after the cover (with marimo chapter) -------
variant "master, declaration after cover"
D="$TMP/master"; copy_project "$D"
set_yaml "$D" 's/^\( *\)type: "Bachelor.*/\1type: master/; s/^\( *\)declaration: end/\1declaration: after-cover/'
if render "$D" "$TMP/master.log"; then
  ok "PDF rendered (with marimo chapter)"
  has "$D" "Master's thesis" && ok "thesis type" || bad "thesis type"
  has "$D" "I declare that" && ok "declaration text" || bad "declaration text"
  before "$D" "chapter\*{Declaration}" "tableofcontents" && ok "declaration before the contents" \
    || bad "declaration before the contents"
else
  bad "PDF rendered"; tail -30 "$TMP/master.log"
fi

# --- custom declaration text --------------------------------------------------
variant "custom declaration text"
D="$TMP/custom"; copy_project "$D"; no_marimo "$D"
set_yaml "$D" 's/^\( *\)# declaration-text: |.*/\1declaration-text: |\
\1  CUSTOM-SENTINEL with *emphasis*./'
if render "$D" "$TMP/custom.log"; then
  has "$D" "CUSTOM-SENTINEL with \\\\emph{emphasis}" && ok "custom text as Markdown" || bad "custom text as Markdown"
  has "$D" "I declare that" && bad "built-in text replaced" || ok "built-in text replaced"
else
  bad "PDF rendered"; tail -30 "$TMP/custom.log"
fi

# --- no declaration -----------------------------------------------------------
variant "declaration: none"
D="$TMP/none"; copy_project "$D"; no_marimo "$D"
set_yaml "$D" 's/^\( *\)declaration: end/\1declaration: none/'
if render "$D" "$TMP/none.log"; then
  has "$D" "chapter\*{Declaration}" && bad "no declaration" || ok "no declaration"
else
  bad "PDF rendered"; tail -30 "$TMP/none.log"
fi

# --- invalid declaration value must stop the render ---------------------------
variant "declaration: sideways (invalid)"
D="$TMP/invalid"; copy_project "$D"; no_marimo "$D"
set_yaml "$D" 's/^\( *\)declaration: end/\1declaration: sideways/'
if render "$D" "$TMP/invalid.log"; then
  bad "render fails"
else
  grep -q "must be one of: end, after-cover, none" "$TMP/invalid.log" && ok "render fails with a clear message" \
    || { bad "clear error message"; tail -10 "$TMP/invalid.log"; }
fi

# --- theses are written in English: another language must stop the render ----
variant "lang: de-DE (not allowed)"
D="$TMP/de"; copy_project "$D"; no_marimo "$D"
set_yaml "$D" 's/^lang: en-US/lang: de-DE/'
if render "$D" "$TMP/de.log"; then
  bad "render fails"
else
  grep -q "theses are written in English" "$TMP/de.log" && ok "render fails with a clear message" \
    || { bad "clear error message"; tail -10 "$TMP/de.log"; }
fi

# --- British English is fine ---------------------------------------------------
variant "lang: en-GB"
D="$TMP/gb"; copy_project "$D"; no_marimo "$D"
set_yaml "$D" 's/^lang: en-US/lang: en-GB/'
if render "$D" "$TMP/gb.log"; then
  has "$D" "Submitted by:" && ok "English labels" || bad "English labels"
else
  bad "PDF rendered"; tail -30 "$TMP/gb.log"
fi

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

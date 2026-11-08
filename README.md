# TH Köln Thesis Template (Quarto)

A [Quarto](https://quarto.org) template for Bachelor's and Master's theses at
TH Köln, based on the official LaTeX template for academic theses (KOMA-Script
`scrreprt`, biblatex, glossaries). You write Markdown; the layout comes from a
Quarto extension and the PDF is typeset with LuaLaTeX.

> **Status.** This is an independently maintained Quarto adaptation of the
> TH Köln LaTeX thesis template, not an official TH Köln publication. Your
> examination regulations determine the mandatory formatting, the wording of
> the declaration and which tools and assistance are permitted.

- Cover page, declaration and all labels from `_quarto.yml` (theses are written in English)
- Table of contents, lists of figures/tables/listings/algorithms, glossary,
  abbreviations and symbols inserted automatically after the abstract
- Numbered, cross-referenced equations ("Equation (2.1)"), figures, tables,
  listings, algorithms (with a List of Algorithms), and theorems, definitions,
  lemmas, corollaries, propositions, examples and remarks (one shared counter,
  e.g. Definition 3.1, Theorem 3.2) — the few differences from Quarto's
  defaults are explained in chapter 3 of the template ("Differences from
  Quarto's Defaults")
- biblatex citations (style `alphabetic`), TikZ/pgfplots
- Optional: [CryptoBib](https://cryptobib.di.ens.fr) for cryptography references
- Optional: Python in [marimo](https://marimo.io) cells — figures and tables
  generated from your data on every render
- Every push to GitHub renders the PDF (*Actions* tab)

The rendered template is its own manual: chapter 3 explains writing with
Quarto, chapter 4 citing. **[Preview (PDF)](https://stavroskousidis.github.io/thk-thesis-quarto/thesis.pdf)**

**Contents:** [1. Start your thesis](#1-start-your-thesis) ·
[2. Write](#2-write) · [3. Optional: CryptoBib](#3-optional-cryptobib) ·
[4. Optional: Python with marimo](#4-optional-python-with-marimo) ·
[5. Final submission](#5-final-submission) · [Reference](#reference) ·
[Comparison with the LaTeX template](#comparison-with-the-th-köln-latex-template) ·
[For maintainers](#for-maintainers)

## 1. Start your thesis

You need: [Quarto](https://quarto.org/docs/get-started/) ≥ 1.9.20, a TeX
distribution with LuaLaTeX and Biber (TeX Live, MacTeX, MiKTeX, or
`quarto install tinytex` followed by `make tinytex-packages`), git and `make`.
[uv](https://docs.astral.sh/uv/getting-started/installation/) is needed only if
a chapter uses marimo cells (`make check` tells you). An editor with Quarto support helps: VS Code or Positron with the
Quarto extension, or RStudio.

1. On GitHub: **Use this template → Create a new repository**, private, and
   add your supervisor as collaborator. Clone it.
2. `make check` — checks the programs, the Quarto version and the LaTeX
   packages, and renders a short test document. Fix whatever it reports.
3. `make` — renders the full template to `_book/thesis.pdf`.

Then work through this checklist once:

- [ ] `_quarto.yml`, `book:` — title, author, date
- [ ] `_quarto.yml`, `thesis:` — replace the placeholders: `type: bachelor` or
      `type: master`, your degree, programme, faculty, matriculation number,
      address, e-mail, reviewers, place
- [ ] `lang:` — `en-US` or `en-GB` (theses are written in English)
- [ ] Declaration: **check the wording against your examination regulations**;
      set `declaration-text` if it differs, and `declaration:` to `end`,
      `after-cover` or `none`
- [ ] Delete `nocite` in `_quarto.yml` and the note in `references.qmd`
      (they produce the template's reading list)
- [ ] Replace the template chapters in `chapters/` and `appendices/` and list
      yours under `book:` in `_quarto.yml`
- [ ] Replace `bib/references.bib`, `tex/glossary.tex`, `images/`, `data/`
      with your own (keep `tex/macros.tex` if you use its commands)
- [ ] Not using Python cells: remove the `engine: marimo` front matter and the
      marimo section from chapter 3 (or the whole chapter)
- [ ] `make`, look at the PDF, commit, push

Without `make` (e.g. on Windows): `quarto render`, `quarto preview`, and the
git commands in the [Makefile](Makefile).

## 2. Write

- `make preview` — live preview; the PDF updates whenever you save.
- `make` — render once.
- One file per chapter in `chapters/`; order in `_quarto.yml`.
- Your LaTeX macros: `tex/macros.tex`; glossary entries: `tex/glossary.tex`.
- Citation keys that are not in any `.bib` file are listed at the start of
  each render, with file and line.
- The PDF built by GitHub after every push is under *Actions → latest run →
  thesis-pdf*.

## 3. Optional: CryptoBib

Only for theses that cite cryptography papers. `make cryptobib` adds the
official [`cryptobib/export_crossref`](https://github.com/cryptobib/export_crossref)
as a shallow git submodule in `bib/cryptobib/`; commit afterwards. Cite with
CryptoBib keys, e.g. `[@C:BonFra01]`. Co-authors or your supervisor run
`make init` once after cloning.

The database has more than 90 000 entries (32 MB); biber would need about 40 s
to read it on every render. So before every render `scripts/cryptobib-subset.ts`
copies only what the thesis cites into `bib/cryptobib.bib` (committed; under a
second):

1. it reads the book's files (`book:` in `_quarto.yml`, plus `{{< include >}}`d
   files and `\input` `.tex` files) and `nocite`;
2. collects Markdown citations (`@key`, `[@key]`, `@{key}`) and `\cite`-family
   commands in raw LaTeX — not in code blocks, inline code or HTML comments;
3. copies these entries from `crypto_crossref.bib`, the proceedings they
   `crossref`, and the `@string` abbreviations they use from `abbrev1.bib`;
4. reports citation keys found in no `.bib` file.

Limits: citations generated at run time inside marimo cells are not seen — cite
such keys once in the text or in `nocite`. `CRYPTOBIB_STRICT=1` turns
unresolved keys into an error. `make cryptobib-subset CRYPTOBIB_ABBREV=abbrev3`
selects shorter venue names (`abbrev0` … `abbrev3`). The proceedings volumes
themselves are not printed (biblatex `mincrossrefs=999`).

Why a submodule in the thesis repository and not in the template: GitHub's
template button does not reliably copy submodules, and adding it at setup
time gets the current CryptoBib.

## 4. Optional: Python with marimo

Chapters can contain Python cells that [marimo](https://marimo.io) runs on
every render (official [quarto-marimo](https://github.com/marimo-team/quarto-marimo)
engine, included in `_extensions/marimo/`). Section 3.8 of the template shows
the pattern for numbered figures and tables. A chapter with cells declares the
engine and **exact** package versions in its front matter:

```yaml
---
engine: marimo
pyproject: |
  requires-python = "==3.13.*"
  dependencies = [
    "marimo==0.25.2",
    "matplotlib==3.11.2",
    "pandas==3.1.1",
    "tabulate==0.10.0",
  ]
---
```

uv installs them into an isolated, cached environment. Indirect dependencies
(numpy, …) are frozen by a date: `UV_EXCLUDE_NEWER` in `_environment` — uv
uses no package release published after it. `make python-date` moves it to
today; do that on purpose, render, check your results, commit.

Known limitations of quarto-marimo 0.5.0:

- `#| label: fig-...` / `#| fig-cap:` on a cell are ignored, and a plot returned
  directly becomes an unnumbered PNG — hence the `figure()` helper in 3.8.
- In a chapter with marimo cells, a listing marked `{#lst-x .python}` is counted
  as a cell and the render stops ("marimo compiler returned N cells for M source
  blocks"). Write `.py` instead.
- `pyproject` must be set in every chapter with cells; one in `_quarto.yml` is
  not used.
- Saving a chapter in the marimo editor adds a `title:` line; develop longer
  analyses in a separate notebook and move the final code into the chapter.

## 5. Final submission

The submitted PDF must be reproducible from the repository.

1. Do **not** run `make update-template` or `make python-date` after this point.
2. `make warnings` — render; fix what it lists, then check the PDF, in particular
   cover page and declaration.
3. `make versions > build-info.txt` — records Quarto, Pandoc, TeX, Biber,
   biblatex, uv, extension versions, the Python package date and the
   CryptoBib commit. Commit it.
4. `git tag v1.0-submitted && git push --tags` — GitHub renders the tagged
   version and attaches the PDF to a release.

Everything in the repository that determines the PDF is then in the tagged
commit: the text, `_quarto.yml`, the extensions in `_extensions/`,
`bib/cryptobib.bib`, the CryptoBib submodule commit, exact versions of the
directly used Python packages and `_environment`. The GitHub build uses a
pinned Quarto version (see `.github/workflows/render.yml`).

This makes the build *repeatable*, not bit-for-bit reproducible: the TeX
distribution and its packages are not pinned (TinyTeX and `tlmgr` install
current versions), and `UV_EXCLUDE_NEWER` freezes indirect Python packages by
date, which is not a full lock file. `build-info.txt` records the versions
actually used, including the TeX Live release, so the build can be
reconstructed for an archived thesis.

## Reference

### Make targets

`make` renders the PDF; `make help` lists all targets. Commands are not
echoed; `make V=1 <target>` shows them.

| Target | What it does |
|---|---|
| `make` / `make pdf` | Render the thesis to `_book/thesis.pdf` |
| `make preview` | Render and update the PDF on every save |
| `make check` | Check programs (uv only if a chapter uses marimo), Quarto version, LaTeX packages; quick test render |
| `make warnings` | Render and list LaTeX warnings and overfull/underfull boxes with their source lines (`STRICT=1`: fail if there are any) |
| `make tinytex-packages` | With TinyTeX: install Biber and all LaTeX packages the format needs |
| `make test` | All tests (`test-bib` and `test-render`) |
| `make test-bib` | Regression tests of the CryptoBib extraction (fixtures in `tests/fixtures/`) |
| `make test-render` | Render variants (declaration, pagination, missing `references.qmd`, invalid settings), check numbering and order, and require zero LaTeX warnings for the full template |
| `make versions` | Print all tool and package versions |
| `make python-date` | Move the Python package date in `_environment` to today |
| `make init` | After cloning: fetch the CryptoBib submodule |
| `make cryptobib` | Optional: add CryptoBib |
| `make cryptobib-subset` | Regenerate `bib/cryptobib.bib` (also runs on every render) |
| `make cryptobib-update` | Update CryptoBib and regenerate the subset |
| `make update-template` | Install the extensions of the latest template release (`TEMPLATE_VERSION=v1.0.0` for a specific one) |
| `make clean` / `make distclean` | Remove intermediate files / also the PDF |

### Configuration (`thesis:` in `_quarto.yml`)

| Key | Values |
|---|---|
| `type` | `bachelor` or `master` (the template shows the free-text placeholder "Bachelor's or Master's thesis") |
| `degree`, `program`, `faculty` | Text on the cover page |
| `student-id`, `address` (list), `email` | Optional rows on the cover page |
| `supervisor`, `second-reviewer` | Reviewers |
| `place` | Place before the date on the cover page |
| `declaration` | `end` (default), `after-cover`, `none`; other values stop the render |
| `declaration-text` | Replaces the default wording (Markdown) |
| `lists` | `toc`, `figures`, `tables`, `listings`, `algorithms`, `glossary`, `acronyms`, `symbols`: `true`/`false` |
| `labels` | Override any label, e.g. `labels: { supervisor: "Supervisor:" }` |

Theses are written in English: `lang` must be `en-US` or `en-GB`; any other
language stops the render. Single labels can be changed with `labels:`.

### Repository layout

| Path | Purpose |
|---|---|
| `_quarto.yml` | Title, author, chapter order, thesis data, language, bibliography |
| `_environment` | `UV_EXCLUDE_NEWER`: date that freezes Python packages |
| `index.qmd` | Abstract (front matter, Roman page numbers) |
| `chapters/`, `appendices/`, `references.qmd` | Chapters, appendices, position of the bibliography |
| `bib/references.bib` | Your own BibTeX entries (e.g. exported from Zotero) |
| `bib/cryptobib/`, `bib/cryptobib.bib` | CryptoBib submodule; generated subset (do not edit) |
| `tex/macros.tex`, `tex/glossary.tex` | Your LaTeX macros; glossary, abbreviations, symbols |
| `images/`, `figures/`, `data/` | Images, TikZ figures, data |
| `_extensions/thk-thesis/` | The format — do not edit; `make update-template` |
| `_extensions/marimo/` | quarto-marimo engine, tested version |
| `scripts/` | CryptoBib extraction and its tests |
| `tests/` | Smoke tests and test fixtures |
| `_generated/` | Figures written by marimo cells (not committed) |

## Comparison with the TH Köln LaTeX template

Checked against the LaTeX template (November 2024) by rendering both and
comparing them page by page; `make test-render` guards the structural points.

| Aspect | Compared with the LaTeX template |
|---|---|
| Page size, margins, text width, fonts, heading styles | Same (KOMA-Script `scrreprt`, Latin Modern, LuaLaTeX) |
| Running header (chapter title) and page numbers | Same |
| Cover page: colour bar, layout, labels | Same; values come from `_quarto.yml`; an "Email:" label was added |
| Page numbering | Same: cover unnumbered, abstract page I, Roman front matter, chapter 1 on page 1 |
| Order of the lists | Same: contents, tables, figures, glossary, abbreviations, symbols; additionally listings and algorithms if the thesis has any |
| Abstract, declaration in the table of contents | Same: not listed |
| Contents title | "Contents" (the LaTeX template says "Content") |
| Bibliography, appendix, declaration | Same order and titles ("Bibliography", "Appendix") |
| Citation style | Same (biblatex/biber, `alphabetic`) |
| Glossaries | Same lists; sorted by LaTeX (`\makenoidxglossaries`), no external tool |
| Source code | Quarto's syntax highlighting instead of the `listings` package |
| Numbering of statements, equation references | Template additions, see "Differences from Quarto's Defaults" in chapter 3 |

## Versions

The template is versioned with git tags `vMAJOR.MINOR.PATCH`
(see [CHANGELOG.md](CHANGELOG.md)):

- **Patch** (1.0.x): fixes; the layout of existing theses does not change.
- **Minor** (1.x.0): new features or options; existing theses render the same
  unless they opt in, but page breaks may shift slightly.
- **Major** (x.0.0): layout or configuration changes that need action.

A thesis keeps the extension versions it was created with until
`make update-template` is run on purpose. A template release bundles the
thesis format with the quarto-marimo version it was tested with, so both are
always updated together. During writing, updating to a new minor release is
fine; after submission, never.

## For maintainers

- Layout changes go into `_extensions/thk-thesis/` only. Bump `version` in
  `_extension.yml`, add a CHANGELOG entry, run `make test`, tag `vX.Y.Z` and
  create a GitHub release. Students run `make update-template`.
- A new quarto-marimo version: `quarto update extension marimo-team/quarto-marimo`
  in this repository, `make test`, then release as above.
- After upgrading Quarto or Pandoc (e.g. the version pinned in CI), run
  `make test`: the shared statement counter, the List of Algorithms and the
  equation references depend on how Quarto generates LaTeX, and the smoke tests
  check exactly these.
- CI (`.github/workflows/render.yml`): the render job runs with read-only
  permissions; only the release job, for `v*` tags pushed to the repository,
  may write (to attach the PDF). The smoke tests run only in this repository.
- Mark the repository as a template: *Settings → General → Template repository*.
- Public preview: every push to `main` of this repository publishes the rendered
  template to <https://stavroskousidis.github.io/thk-thesis-quarto/> (job `pages`;
  needs *Settings → Pages → Source: GitHub Actions*). Thesis repositories created
  from the template never publish anything: the job is limited to this repository.
- Alternative to the template button: `quarto use template
  stavroskousidis/thk-thesis-quarto`.

## Credits

Content of the template text: TH Köln (Stephan Freichel, Maria-Anna
Worth, Susanne Neuzerling, Andreas Bissels, Katharina Bata, André Ulrich, Jan
Salmen, Lynne Lörler). Quarto version: Stavros Kousidis.

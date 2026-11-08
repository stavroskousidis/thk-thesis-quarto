# Makefile for a TH Köln thesis written with Quarto.
# `make` renders the PDF; `make help` lists all targets.
# Commands are not echoed; use `make V=1` to see them.

QUARTO        ?= quarto
PDF           := _book/thesis.pdf
TEMPLATE_REPO := stavroskousidis/thk-thesis-quarto
# Empty = latest release; or a tag, e.g. TEMPLATE_VERSION=v1.0.0
TEMPLATE_VERSION ?=
QUARTO_MIN    := 1.9.20

CRYPTOBIB_URL := https://github.com/cryptobib/export_crossref
CRYPTOBIB_DIR := bib/cryptobib
# Level of detail of venue names: abbrev0 (most) ... abbrev3 (least)
CRYPTOBIB_ABBREV ?= abbrev1
export CRYPTOBIB_ABBREV

# LaTeX files the format needs (checked by `make check`)
TEX_FILES := scrreprt.cls scrlayer-scrpage.sty biblatex.sty glossaries.sty \
             tracklang.sty mfirstuc.sty pgfplots.sty selnolig.sty csquotes.sty \
             microtype.sty mathtools.sty fontspec.sty bookmark.sty tcolorbox.sty \
             fontawesome5.sty fvextra.sty scrhack.sty algpseudocodex.sty

.DEFAULT_GOAL := pdf
MAKEFLAGS += --no-print-directory
ifndef V
.SILENT:
endif

# TeX Live package names for TinyTeX (`make tinytex-packages`)
TINYTEX_PACKAGES := biber biblatex koma-script glossaries glossaries-english \
             datatool-english datatool-regions tracklang mfirstuc xfor \
             datatool pgf pgfplots selnolig csquotes microtype mathtools tcolorbox \
             fontawesome5 environ pdfcol tikzfill bookmark babel-english \
             hyphen-english lualatex-math unicode-math fontspec caption float \
             fancyvrb fvextra lineno upquote algpseudocodex algorithmicx \
             fifo-stack tabto-ltx totcount varwidth framed booktabs etoolbox \
             xcolor lm luatexbase

.PHONY: tinytex-packages help pdf preview warnings check test test-bib test-render versions python-date \
        init cryptobib cryptobib-subset cryptobib-update update-template clean distclean

help: ## Show this help
	echo "Usage: make <target>"
	echo
	awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-17s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	echo
	echo "'make' alone renders the PDF to $(PDF). Add V=1 to see the commands."

# --- Writing -----------------------------------------------------------------

pdf: ## Render the thesis to PDF (default)
	$(QUARTO) render

preview: ## Render and re-render on every save (live preview)
	$(QUARTO) preview

warnings: ## Render and list LaTeX warnings and bad boxes (STRICT=1: fail if there are any)
	$(QUARTO) render -M latex-clean:false -M keep-tex:true
	echo; tests/latex-warnings.sh || [ -z "$(STRICT)" ]

tinytex-packages: ## With TinyTeX only: install Biber and all LaTeX packages the format needs
	tlmgr update --self
	tlmgr install $(TINYTEX_PACKAGES)

# --- Checks and tests --------------------------------------------------------

check: ## Check tools, versions and LaTeX packages, then do a quick test render
	ok=1; \
	echo "Programs:"; \
	for tool in $(QUARTO) lualatex biber git kpsewhich; do \
	  if command -v $$tool >/dev/null 2>&1; then \
	    printf "  %-10s ok\n" $$tool; \
	  else \
	    printf "  %-10s MISSING\n" $$tool; ok=0; \
	  fi; \
	done; \
	if scripts/uses-marimo.sh; then \
	  if command -v uv >/dev/null 2>&1; then printf "  %-10s ok (marimo cells)\n" uv; \
	  else printf "  %-10s MISSING (needed for the marimo cells in your chapters)\n" uv; ok=0; fi; \
	else \
	  printf "  %-10s not needed (no marimo cells)\n" uv; \
	fi; \
	if command -v $(QUARTO) >/dev/null 2>&1; then \
	  qv=$$($(QUARTO) --version); \
	  if [ "$$(printf '%s\n%s\n' $(QUARTO_MIN) $$qv | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$(QUARTO_MIN)" ]; then \
	    echo "  Quarto $$qv ok (>= $(QUARTO_MIN))"; \
	  else \
	    echo "  Quarto $$qv TOO OLD (need >= $(QUARTO_MIN))"; ok=0; \
	  fi; \
	fi; \
	if command -v kpsewhich >/dev/null 2>&1; then \
	  echo "LaTeX packages:"; missing=""; \
	  for f in $(TEX_FILES); do \
	    kpsewhich $$f >/dev/null 2>&1 || missing="$$missing $$f"; \
	  done; \
	  if [ -z "$$missing" ]; then echo "  all found"; \
	  elif [ -d "$$HOME/.TinyTeX" ] || [ -d "$$HOME/Library/TinyTeX" ]; then \
	    echo "  missing:$$missing (TinyTeX installs them on the first render)"; \
	  else \
	    echo "  MISSING:$$missing"; ok=0; \
	  fi; \
	fi; \
	if [ $$ok = 0 ]; then \
	  echo; \
	  echo "Install Quarto >= $(QUARTO_MIN) (https://quarto.org/docs/get-started/), a TeX"; \
	  echo "distribution with the packages above (TeX Live, MacTeX, MiKTeX, or"; \
	  echo "'quarto install tinytex' and 'make tinytex-packages'), and -- only for"; \
	  echo "marimo cells -- uv (https://docs.astral.sh/uv/getting-started/installation/)."; \
	  exit 1; \
	fi; \
	echo "Test render:"; \
	if tests/smoke.sh minimal >/tmp/thk-check.log 2>&1; then \
	  echo "  ok -- everything is ready."; \
	else \
	  cat /tmp/thk-check.log; echo; echo "The test render FAILED (log above)."; exit 1; \
	fi

test: test-bib test-render ## Run all tests (CryptoBib extraction, renders)

test-bib: ## Test the CryptoBib extraction against fixtures
	$(QUARTO) run scripts/cryptobib-subset.test.ts

test-render: ## Render declaration variants and invalid settings and check them
	tests/smoke.sh all

# --- Reproducibility -----------------------------------------------------------

versions: ## Print all tool and package versions (keep with the submitted PDF)
	echo "Quarto:        $$($(QUARTO) --version)"
	echo "Pandoc:        $$($(QUARTO) pandoc --version | head -1)"
	echo "TeX:           $$(tex --version | head -1)"
	echo "LuaLaTeX:      $$(lualatex --version | head -1)"
	echo "Biber:         $$(biber --version)"
	echo "biblatex:      $$(sed -n 's/.*abx@version{\([0-9.]*\)}.*/\1/p' "$$(kpsewhich biblatex.sty)" 2>/dev/null | head -1)"
	echo "uv:            $$(uv --version 2>/dev/null || echo 'not installed')"
	echo "thk-thesis:    $$(grep '^version:' _extensions/thk-thesis/_extension.yml | cut -d' ' -f2)"
	echo "quarto-marimo: $$(grep '^version:' _extensions/marimo/_extension.yml | cut -d' ' -f2)"
	echo "Python date:   $$(grep '^UV_EXCLUDE_NEWER=' _environment | cut -d= -f2)"
	echo "CryptoBib:     $$(git -C $(CRYPTOBIB_DIR) log -1 --format='%h %cs' 2>/dev/null || echo 'not used')"
	echo "Thesis commit: $$(git log -1 --format='%h %cs' 2>/dev/null)"

python-date: ## Move the Python package date (UV_EXCLUDE_NEWER in _environment) to today
	d=$$(date -u +%Y-%m-%dT00:00:00Z); \
	sed -i.bak "s/^UV_EXCLUDE_NEWER=.*/UV_EXCLUDE_NEWER=$$d/" _environment && rm -f _environment.bak; \
	echo "UV_EXCLUDE_NEWER=$$d -- render, check your results, then commit _environment."

# --- CryptoBib -----------------------------------------------------------------

init: ## After cloning: fetch the CryptoBib submodule (if the thesis uses it)
	git submodule update --init --depth 1

cryptobib: ## Optional: add CryptoBib as submodule in bib/cryptobib
	if [ -f $(CRYPTOBIB_DIR)/crypto_crossref.bib ]; then \
	  echo "CryptoBib is already present in $(CRYPTOBIB_DIR)."; \
	elif git config -f .gitmodules submodule.$(CRYPTOBIB_DIR).url >/dev/null 2>&1; then \
	  git submodule update --init --depth 1 $(CRYPTOBIB_DIR); \
	else \
	  echo "Adding CryptoBib (about 35 MB) as a shallow submodule ..."; \
	  git submodule add --depth 1 $(CRYPTOBIB_URL) $(CRYPTOBIB_DIR) && \
	  git config -f .gitmodules submodule.$(CRYPTOBIB_DIR).shallow true; \
	fi
	$(MAKE) cryptobib-subset
	git add .gitmodules $(CRYPTOBIB_DIR) bib/cryptobib.bib
	echo
	echo "Commit with: git commit -m 'Add CryptoBib' && git push"

cryptobib-subset: ## Copy the cited CryptoBib entries to bib/cryptobib.bib (also runs on every render)
	$(QUARTO) run scripts/cryptobib-subset.ts

cryptobib-update: ## Update CryptoBib to the latest version
	git submodule update --remote --depth 1 $(CRYPTOBIB_DIR)
	$(MAKE) cryptobib-subset
	git add $(CRYPTOBIB_DIR) bib/cryptobib.bib
	echo "Commit with: git commit -m 'Update CryptoBib'"

# --- Template ------------------------------------------------------------------

update-template: ## Install the thesis format and marimo extension of a template release
	echo "Installing the extensions of $(TEMPLATE_REPO)$(if $(TEMPLATE_VERSION),@$(TEMPLATE_VERSION), (latest release))."
	echo "Do NOT do this after submitting: it may change the layout. See README, 'Versions'."
	$(QUARTO) add $(TEMPLATE_REPO)$(if $(TEMPLATE_VERSION),@$(TEMPLATE_VERSION)) --no-prompt
	echo "Review the changes with 'git diff _extensions', render, and commit."

clean: ## Remove LaTeX intermediate files
	rm -f *.aux *.log *.bbl *.bcf *.blg *.run.xml *.toc *.out *.lo? \
	      *.gl? *.ac? *.sl? *.ist index.tex thesis.tex
	rm -rf .quarto _generated
	rm -f chapters/*.pdf.md appendices/*.pdf.md *.pdf.md

distclean: clean ## Also remove the rendered PDF
	rm -rf _book

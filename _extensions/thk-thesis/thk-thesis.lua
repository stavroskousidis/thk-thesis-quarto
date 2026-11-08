--[[
thk-thesis.lua -- structural pieces of the TH Köln thesis format (PDF/LaTeX)

  * fills the labels of the cover page (theses are written in English)
  * inserts table of contents, list of figures/tables/listings/algorithms and the
    glossaries between the front matter (abstract) and chapter 1, and
    switches page numbering from Roman to Arabic there
  * places the bibliography where the `::: {#refs}` div is (or, without it,
    before the appendix)
  * adds the declaration of authorship (after the cover or at the end)

Everything is configured in the `thesis:` block of _quarto.yml.
]]

local stringify = pandoc.utils.stringify

local LABELS = {
  en = {
    cover        = "Title page",
    contents     = "Contents",
    kind         = { bachelor = "Bachelor's thesis", master = "Master's thesis" },
    purpose      = "to obtain the academic degree",
    program      = "in the degree program",
    faculty      = "at the",
    university   = "of TH Köln – University of Applied Sciences",
    author       = "Submitted by:",
    ["student-id"] = "Matriculation no.:",
    address      = "Address:",
    email        = "Email:",
    supervisor   = "Submitted to:",
    ["second-reviewer"] = "Second reviewer:",
    glossary     = "Glossary",
    acronyms     = "List of Abbreviations",
    symbols      = "List of Symbols",
    listings     = "List of Listings",
    declaration  = "Declaration",
    ["place-date"] = "Place, date",
    signature    = "Signature",
    ["declaration-text"] = "I declare that I have written this thesis independently. "
      .. "I have acknowledged all passages taken verbatim or in spirit from published "
      .. "or unpublished works of others or from the author himself/herself. All sources "
      .. "and aids that I have used for the thesis are indicated. The thesis has not been "
      .. "submitted to any other examination authority with the same content or in "
      .. "essential parts.",
  },
}

local DECLARATION_POSITIONS = { ["end"] = true, ["after-cover"] = true, none = true }

local function is_latex()
  return quarto.doc.is_format("latex") or quarto.doc.is_format("pdf")
end

local function raw(s) return pandoc.RawBlock("latex", s) end

local function bool(v, default)
  if v == nil then return default end
  if type(v) == "boolean" then return v end
  local s = stringify(v):lower()
  return not (s == "false" or s == "no" or s == "0" or s == "")
end

local function as_list(v)
  if v == nil then return {} end
  if pandoc.utils.type(v) == "List" then return v end
  return { v }
end

-- configuration collected in Meta, used in Pandoc
local cfg = {}

-- Labels go through the Markdown reader: typographic quotes and dashes.
local function inl(s)
  return pandoc.MetaInlines(pandoc.utils.blocks_to_inlines(pandoc.read(s, "markdown").blocks))
end

local function process_meta(meta)
  local lang = meta.lang and stringify(meta.lang):lower() or "en"
  if lang:sub(1, 2) ~= "en" then
    -- Theses are written in English; stop instead of producing mixed labels.
    quarto.log.error("thk-thesis: theses are written in English, but lang is '" .. lang
      .. "'. Use lang: en-US or en-GB.")
    os.exit(1)
  end
  local L = LABELS.en
  local thesis = meta.thesis or {}

  -- user overrides: thesis.labels.<key>
  local function label(key)
    if thesis.labels and thesis.labels[key] then return thesis.labels[key] end
    return inl(L[key])
  end

  local ttype = thesis.type and stringify(thesis.type):lower() or "bachelor"
  local kind = L.kind[ttype] and inl(L.kind[ttype]) or thesis.type

  -- rows of the table on the cover page
  local rows = pandoc.List()
  local function add(key, value, gap)
    if value == nil then return end
    rows:insert({ label = label(key), value = value, gap = gap and true or nil })
  end
  local author = meta.author
  if pandoc.utils.type(author) == "List" then author = author[1] end
  if author and type(author) == "table" and author.name then author = author.name end
  add("author", author)
  add("student-id", thesis["student-id"])
  local addr = as_list(thesis.address)
  for i, line in ipairs(addr) do
    rows:insert({ label = i == 1 and label("address") or inl(""), value = line })
  end
  add("email", thesis.email)
  if #rows > 0 then rows[#rows].gap = true end
  add("supervisor", thesis.supervisor)
  add("second-reviewer", thesis["second-reviewer"])

  meta.thk = {
    kind = kind,
    purpose = label("purpose"),
    rows = rows,
    labels = {
      cover = label("cover"),
      program = label("program"),
      faculty = label("faculty"),
      university = label("university"),
    },
  }

  -- remember everything needed for the body
  local lists = thesis.lists or {}
  cfg.lists = {
    toc      = bool(lists.toc, true),
    figures  = bool(lists.figures, true),
    tables   = bool(lists.tables, true),
    listings = bool(lists.listings, false),
    algorithms = bool(lists.algorithms, true),
    glossary = bool(lists.glossary, true),
    acronyms = bool(lists.acronyms, true),
    symbols  = bool(lists.symbols, true),
  }
  cfg.label = function(key) return stringify(label(key)) end
  cfg.declaration = thesis.declaration and stringify(thesis.declaration):lower() or "end"
  if cfg.declaration == "false" then cfg.declaration = "none" end -- YAML `declaration: false`
  if not DECLARATION_POSITIONS[cfg.declaration] then
    -- Quarto logs a Lua error() and renders anyway; stop the render instead.
    quarto.log.error("thk-thesis: thesis.declaration is '" .. cfg.declaration
      .. "', but must be one of: end, after-cover, none")
    os.exit(1)
  end
  -- Built-in and custom text take the same path: Markdown -> blocks.
  if thesis["declaration-text"] then
    cfg.declaration_blocks = pandoc.Blocks(thesis["declaration-text"])
  else
    cfg.declaration_blocks = pandoc.read(L["declaration-text"], "markdown").blocks
  end
  cfg.place = thesis.place
  return meta
end

local function front_lists()
  local l = cfg.lists
  local s = { "\\cleardoublepage" }
  if l.toc then
    s[#s + 1] = "\\pdfbookmark[0]{" .. cfg.label("contents") .. "}{toc}"
    s[#s + 1] = "\\tableofcontents"
  end
  -- tables before figures, as in the TH Köln LaTeX template
  if l.tables then s[#s + 1] = "\\listoftables" end
  if l.figures then s[#s + 1] = "\\listoffigures" end
  if l.listings then
    s[#s + 1] = "\\ifdefined\\listoflistings\\listoflistings\\fi"
  end
  if l.algorithms and cfg.has_algorithms then
    s[#s + 1] = "\\listofthkalgorithms"
  end
  if l.glossary then
    s[#s + 1] = "\\printnoidxglossary[type=main,title={" .. cfg.label("glossary") .. "}]"
  end
  if l.acronyms then
    s[#s + 1] = "\\printnoidxglossary[type=\\acronymtype,title={" .. cfg.label("acronyms") .. "}]"
  end
  if l.symbols then
    s[#s + 1] = "\\printnoidxglossary[type=symbols,sort=def,title={" .. cfg.label("symbols") .. "}]"
  end
  s[#s + 1] = "\\cleardoublepage"
  s[#s + 1] = "\\pagenumbering{arabic}"
  return raw(table.concat(s, "\n"))
end

local function declaration_blocks()
  local blocks = pandoc.List()
  blocks:insert(pandoc.Header(1, cfg.label("declaration"),
    pandoc.Attr("declaration", { "unnumbered", "unlisted" })))
  blocks:extend(cfg.declaration_blocks)
  blocks:insert(raw(table.concat({
    "\\vspace{3cm}",
    "\\noindent",
    "\\begin{tabular}[t]{@{}l@{}}\\rule{0.45\\textwidth}{0.4pt}\\\\ "
      .. cfg.label("place-date") .. "\\end{tabular}%",
    "\\hfill",
    "\\begin{tabular}[t]{@{}l@{}}\\rule{0.45\\textwidth}{0.4pt}\\\\ "
      .. cfg.label("signature") .. "\\end{tabular}",
  }, "\n")))
  return blocks
end

local function process_body(doc)
  local blocks = doc.blocks
  local out = pandoc.List()
  local lists_done = false
  local refs_found = false

  for _, b in ipairs(blocks) do
    if not lists_done and b.t == "Header" and b.level == 1
        and not b.classes:includes("unnumbered") then
      out:insert(front_lists())
      lists_done = true
    end
    if b.t == "Div" and b.identifier == "refs" then
      refs_found = true
      b = raw("\\printbibliography[heading=none]")
    end
    out:insert(b)
  end

  if not lists_done then
    -- no numbered chapter: put the lists at the very beginning
    out:insert(1, front_lists())
  end

  -- No `::: {#refs}` div (references.qmd removed): the bibliography still goes
  -- before the appendix -- Quarto starts it with a "book part" div, the last
  -- one in the book (parts of the main text come before it) -- or, without
  -- appendices, at the end of the main text. Either way before the declaration.
  if not refs_found then
    local bib = raw("\\printbibliography[heading=bibintoc]")
    local pos
    local book = doc.meta.book
    if book and book.appendices and #book.appendices > 0 then
      for i = #out, 1, -1 do
        if out[i].t == "Div" and out[i].classes:includes("quarto-book-part") then
          pos = i
          break
        end
      end
    end
    if pos then out:insert(pos, bib) else out:insert(bib) end
  end

  if cfg.declaration == "after-cover" then
    local d = declaration_blocks()
    d:insert(raw("\\cleardoublepage"))
    for i = #d, 1, -1 do out:insert(1, d[i]) end
  elseif cfg.declaration == "end" then
    out:extend(declaration_blocks())
  end

  doc.blocks = out
  return doc
end

-- ---------------------------------------------------------------------------
-- Customization 1: equation references read "Equation (3.1)", matching the
-- number "(3.1)" next to the equation. `-@eq-x` gives "(3.1)".
-- (Quarto's default is "Equation 3.1".)
-- ---------------------------------------------------------------------------
local function equation_ref(cite)
  for _, c in ipairs(cite.citations) do
    if not c.id:match("^eq%-") then return nil end
  end
  local refs = {}
  for _, c in ipairs(cite.citations) do refs[#refs + 1] = "\\eqref{" .. c.id .. "}" end
  local list = refs[1]
  if #refs == 2 then
    list = refs[1] .. " and~" .. refs[2]
  elseif #refs > 2 then
    list = table.concat(refs, ", ", 1, #refs - 1) .. ", and~" .. refs[#refs]
  end
  if cite.citations[1].mode == "SuppressAuthor" then
    return pandoc.RawInline("latex", list)
  end
  return pandoc.RawInline("latex", (#refs == 1 and "Equation" or "Equations") .. "~" .. list)
end

-- ---------------------------------------------------------------------------
-- Customization 2: a List of Algorithms. Algorithms are Quarto's built-in
-- statement type (`::: {#alg-...}`) and are typeset unchanged; this only adds
-- each one, with its number and name, to the list (defined in
-- partials/before-title.tex).
-- ---------------------------------------------------------------------------
-- Quarto turns `::: {#alg-...}` into its own "Theorem" element before user
-- filters run; its `name` is the optional heading, `div` the content.
local function algorithm_entry(thm)
  if not (thm.identifier or ""):match("^alg%-") then return nil end
  cfg.has_algorithms = true
  local name = ""
  if thm.name and pandoc.utils.stringify(thm.name) ~= "" then
    local blocks = pandoc.utils.type(thm.name) == "Block" and { thm.name }
      or { pandoc.Plain(thm.name) }
    name = pandoc.write(pandoc.Pandoc(blocks), "latex"):gsub("%s+$", "")
  end
  thm.div.content:insert(1, raw("\\addcontentsline{loa}{algorithm}"
    .. "{\\protect\\numberline{\\thealgorithm}" .. name .. "}"))
  return thm
end

return {
  {
    Theorem = function(thm) if is_latex() then return algorithm_entry(thm) end end,
    Cite = function(cite) if is_latex() then return equation_ref(cite) end end,
  },
  {
    Pandoc = function(doc)
      if not is_latex() then return nil end
      doc.meta = process_meta(doc.meta)
      return process_body(doc)
    end,
  },
}

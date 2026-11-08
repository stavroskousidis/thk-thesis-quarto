/**
 * cryptobib-subset.ts -- Quarto pre-render script
 *
 * CryptoBib (bib/cryptobib, a git submodule of cryptobib/export_crossref) has
 * more than 90 000 entries in a 32 MB file; biber needs about 40 s to read it on
 * every render. This script copies only the entries cited in the thesis -- plus
 * the proceedings they crossref and the @string abbreviations they use -- into
 * bib/cryptobib.bib, a small, self-contained BibTeX file.
 *
 * Which citations count:
 *   - only the files of the book (`book:` chapters/appendices in _quarto.yml,
 *     plus files pulled in with {{< include >}}), and `nocite` in _quarto.yml;
 *   - Markdown citations (`@key`, `[@key]`, `@{key}`) in the text, and
 *     \cite-family commands in raw LaTeX blocks and in \input .tex files;
 *   - NOT: fenced code blocks (incl. marimo cells), inline code, HTML comments.
 *     Citations built at run time inside marimo cells are therefore not seen;
 *     cite such keys once in the text or in `nocite`.
 *
 * Citation keys that are neither in bib/references.bib nor in CryptoBib are
 * reported. Set CRYPTOBIB_STRICT=1 to make that an error (exit code 1).
 *
 * It runs automatically before every `quarto render` / `quarto preview`
 * (see `pre-render` in _quarto.yml) with the Deno runtime bundled with Quarto,
 * so nothing has to be installed. Run it by hand with `make cryptobib-subset`;
 * its tests with `make test-bib`.
 *
 * Settings (environment variables):
 *   CRYPTOBIB_ABBREV  abbrev0 | abbrev1 | abbrev2 | abbrev3   (default: abbrev1)
 *   CRYPTOBIB_DB      database file in bib/cryptobib    (default: crypto_crossref.bib)
 *   CRYPTOBIB_STRICT  1 = unresolved citation keys are an error
 */

// ---------------------------------------------------------------------------
// BibTeX scanning
// ---------------------------------------------------------------------------

export interface BibEntry {
  type: string; // lower case, e.g. "inproceedings"
  key: string;
  text: string; // the complete entry as in the source, "@type{key, ...}"
}

export interface BibFile {
  entries: Map<string, BibEntry>;
  strings: Map<string, string>; // lower-case name -> complete "@string{...}"
}

/** Index of the delimiter that closes the one at `open` ({ or ( ). */
function matchingClose(src: string, open: number): number {
  const closeCh = src[open] === "(" ? ")" : "}";
  let depth = 0;
  let inQuote = false;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (c === "\\") { i++; continue; }
    if (c === "{") { depth++; continue; }
    if (c === "}") {
      depth--;
      if (closeCh === "}" && depth === 0) return i;
      continue;
    }
    // quotes delimit values only at brace depth 1 (outside {...} groups)
    if (c === '"' && depth === 1) { inQuote = !inQuote; continue; }
    if (closeCh === ")" && c === ")" && depth === 0 && !inQuote) return i;
  }
  return -1;
}

/**
 * Splits a BibTeX source into entries and @string definitions. Handles
 * {...} and (...) delimiters, nested braces, quotes, @comment and @preamble.
 * Text outside entries is ignored, as BibTeX does.
 */
export function parseBib(src: string): BibFile {
  const entries = new Map<string, BibEntry>();
  const strings = new Map<string, string>();
  const re = /@\s*([A-Za-z]+)\s*([{(])/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    const type = m[1].toLowerCase();
    const open = m.index + m[0].length - 1;
    const close = matchingClose(src, open);
    if (close < 0) break; // unterminated entry: stop, like BibTeX
    const text = src.slice(m.index, close + 1);
    re.lastIndex = close + 1;
    if (type === "comment" || type === "preamble") continue;
    const body = src.slice(open + 1, close);
    if (type === "string") {
      const s = body.match(/^\s*([^\s=]+)\s*=/);
      if (s) strings.set(s[1].toLowerCase(), text);
      continue;
    }
    const k = body.match(/^\s*([^,\s]+)\s*,/);
    if (k) entries.set(k[1], { type, key: k[1], text });
  }
  return { entries, strings };
}

/** Names of @string macros used in the field values of an entry or @string. */
export function macrosUsed(text: string): string[] {
  const open = text.search(/[{(]/);
  let body = text.slice(open + 1, -1);
  let prev: string;
  do { // remove {...} groups, innermost first
    prev = body;
    body = body.replace(/\{[^{}]*\}/g, " ");
  } while (body !== prev);
  body = body.replace(/"[^"]*"/g, " ");
  const names: string[] = [];
  for (const m of body.matchAll(/[=#]\s*([A-Za-z_][\w\-:.+/]*)/g)) {
    names.push(m[1].toLowerCase());
  }
  return names;
}

/**
 * Key of the parent entry in a `crossref` field. In crypto_crossref.bib the
 * value is a macro (`crossref = crypto01,` with `@string{crypto01 = "C01"}`),
 * elsewhere a quoted or braced key.
 */
export function crossrefTarget(entry: string, strings: Map<string, string>): string | null {
  const m = entry.match(/(?:^|[,{(])\s*crossref\s*=\s*(?:"([^"]+)"|\{([^}]+)\}|([A-Za-z_][\w\-:.+/]*))/im);
  if (!m) return null;
  if (m[1] ?? m[2]) return (m[1] ?? m[2]).trim();
  const def = strings.get(m[3].toLowerCase());
  const v = def?.match(/=\s*(?:"([^"]*)"|\{([^}]*)\})\s*[})]\s*$/);
  return v ? (v[1] ?? v[2]).trim() : m[3];
}

// ---------------------------------------------------------------------------
// Citation discovery
// ---------------------------------------------------------------------------

export interface Citation {
  key: string;
  file: string;
  line: number;
}

const PANDOC_KEY =
  /(?<![\p{L}\p{N}_@\\])@(?:\{([^}\s]+)\}|([\p{L}\p{N}_][\p{L}\p{N}_:.#$%&\-+?<>~\/]*))/gu;
const TRAILING_PUNCT = /[:.#$%&\-+?<>~\/]+$/;
const LATEX_CITE = /\\[a-zA-Z]*cite[a-zA-Z]*\*?/g;

/** Quarto cross-reference prefixes: `@fig-x` is not a citation. */
const CROSSREF = /^(fig|tbl|sec|eq|lst|thm|lem|cor|prp|cnj|def|exm|exr|sol|rem|alg|apx)-/;

function lineOf(src: string, index: number): number {
  let n = 1;
  for (let i = 0; i < index; i++) if (src.charCodeAt(i) === 10) n++;
  return n;
}

/** Replace a range by spaces, keeping line breaks (so line numbers stay). */
function blank(s: string): string {
  return s.replace(/[^\n]/g, " ");
}

/** Keys of \cite-like commands, including \cites{a}{b} and optional args. */
export function latexCitations(src: string): { key: string; index: number }[] {
  const out: { key: string; index: number }[] = [];
  for (const m of src.matchAll(LATEX_CITE)) {
    let i = m.index! + m[0].length;
    // read the following [..] and {..} groups
    while (i < src.length) {
      while (src[i] === " " || src[i] === "\t") i++;
      if (src[i] === "[") {
        const j = src.indexOf("]", i);
        if (j < 0) break;
        i = j + 1;
      } else if (src[i] === "{") {
        const j = src.indexOf("}", i);
        if (j < 0) break;
        for (const k of src.slice(i + 1, j).split(",")) {
          if (k.trim()) out.push({ key: k.trim(), index: i });
        }
        i = j + 1;
      } else break;
    }
  }
  return out;
}

/**
 * Citation keys in a Markdown/Quarto source. Code blocks (except raw LaTeX
 * blocks), inline code and HTML comments are ignored. Returns the cleaned
 * source as well, for following {{< include >}} shortcodes.
 */
export function markdownCitations(src: string): { keys: { key: string; index: number }[] } {
  let text = src.replace(/<!--[\s\S]*?-->/g, blank);
  const raw: string[] = [];
  // fenced code blocks: keep raw LaTeX ({=latex}/{=tex}) for \cite scanning
  text = text.replace(
    /^([ \t]*)(`{3,}|~{3,})([^\n]*)\n([\s\S]*?)^\1\2[`~]*[ \t]*$/gm,
    (whole, _ind, _fence, info: string, body: string) => {
      if (/\{=(latex|tex)\}/.test(info)) raw.push(body);
      return blank(whole);
    },
  );
  text = text.replace(/(`+)[\s\S]*?\1/g, blank); // inline code
  const keys: { key: string; index: number }[] = [];
  for (const m of text.matchAll(PANDOC_KEY)) {
    const key = m[1] ?? m[2].replace(TRAILING_PUNCT, "");
    if (!CROSSREF.test(key)) keys.push({ key, index: m.index! });
  }
  for (const k of latexCitations(text)) keys.push(k); // inline raw LaTeX
  for (const body of raw) {
    const at = src.indexOf(body);
    for (const k of latexCitations(body)) keys.push({ key: k.key, index: at + k.index });
  }
  return { keys };
}

// ---------------------------------------------------------------------------
// Project structure
// ---------------------------------------------------------------------------

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}

/** The book's input files from _quarto.yml (`book:` block), in order. */
export function bookFiles(quartoYml: string): string[] {
  const lines = quartoYml.split("\n");
  const start = lines.findIndex((l) => /^book:\s*$/.test(l));
  if (start < 0) return [];
  const files: string[] = [];
  for (let i = start + 1; i < lines.length; i++) {
    const l = lines[i];
    if (/^\S/.test(l)) break; // next top-level key
    const s = l.replace(/#.*$/, "");
    for (const m of s.matchAll(/([\w./\-]+\.(?:qmd|md|ipynb|Rmd))/g)) files.push(m[1]);
  }
  return files;
}

/** The `nocite` keys of _quarto.yml (`@*` is ignored). */
export function nociteKeys(quartoYml: string): string[] {
  const m = quartoYml.match(/^nocite:\s*(\|[^\n]*\n((?:[ \t]+[^\n]*\n?)*)|"([^"]*)"|'([^']*)'|([^\n]*))/m);
  if (!m) return [];
  const text = m[2] ?? m[3] ?? m[4] ?? m[5] ?? "";
  return [...text.matchAll(PANDOC_KEY)].map((x) => x[1] ?? x[2].replace(TRAILING_PUNCT, ""));
}

/** Collect all citations of the project rooted at `root`. */
export async function collectCitations(root: string): Promise<Citation[]> {
  const yml = await Deno.readTextFile(`${root}/_quarto.yml`);
  const cites: Citation[] = nociteKeys(yml).map((key) => ({ key, file: "_quarto.yml", line: 0 }));
  const queue = bookFiles(yml);
  const seen = new Set<string>();
  while (queue.length > 0) {
    const rel = queue.shift()!.replace(/^\.\//, "");
    if (seen.has(rel)) continue;
    seen.add(rel);
    const path = `${root}/${rel}`;
    if (!(await exists(path))) continue;
    const src = await Deno.readTextFile(path);
    const dir = rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/") + 1) : "";
    const found = rel.endsWith(".tex")
      ? latexCitations(src.replace(/(?<!\\)%[^\n]*/g, blank))
      : markdownCitations(src).keys;
    for (const k of found) cites.push({ key: k.key, file: rel, line: lineOf(src, k.index) });
    // follow {{< include file >}} and \input{file}
    for (const m of src.matchAll(/\{\{<\s*include\s+([^\s>]+)\s*>\}\}/g)) {
      queue.push(m[1].startsWith("/") ? m[1].slice(1) : dir + m[1]);
    }
    for (const m of src.matchAll(/\\(?:input|include)\{([^}]+)\}/g)) {
      queue.push(m[1].endsWith(".tex") ? m[1] : `${m[1]}.tex`); // relative to root
    }
  }
  return cites;
}

// ---------------------------------------------------------------------------
// Building the subset
// ---------------------------------------------------------------------------

/** Selected entries (cited + crossref parents) and the @string defs they need. */
export function buildSubset(keys: Iterable<string>, db: BibFile, abbrev: BibFile): string {
  const strings = new Map([...abbrev.strings, ...db.strings]);
  const selected = new Map<string, BibEntry>();
  const queue = [...keys].filter((k) => db.entries.has(k));
  while (queue.length > 0) {
    const k = queue.shift()!;
    if (selected.has(k)) continue;
    const e = db.entries.get(k)!;
    selected.set(k, e);
    const parent = crossrefTarget(e.text, strings);
    if (parent && db.entries.has(parent) && !selected.has(parent)) queue.push(parent);
  }

  // @string definitions in dependency order (definitions before use)
  const ordered: string[] = [];
  const seen = new Set<string>();
  const visit = (name: string) => {
    if (seen.has(name) || !strings.has(name)) return;
    seen.add(name);
    const def = strings.get(name)!;
    for (const dep of macrosUsed(def)) if (dep !== name) visit(dep);
    ordered.push(def);
  };
  for (const e of selected.values()) for (const n of macrosUsed(e.text)) visit(n);

  // entries sorted by key; crossref'ed parents after their children (BibTeX rule)
  const parents = new Set(
    [...selected.values()].map((e) => crossrefTarget(e.text, strings)).filter((x) => x),
  );
  const entries = [...selected.values()].sort((a, b) =>
    Number(parents.has(a.key)) - Number(parents.has(b.key)) || a.key.localeCompare(b.key)
  );
  return [...ordered, "", ...entries.flatMap((e) => [e.text, ""])].join("\n");
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function log(msg: string) {
  console.log(`[cryptobib] ${msg}`);
}

async function writeIfChanged(path: string, content: string) {
  const old = (await exists(path)) ? await Deno.readTextFile(path) : null;
  if (old !== content) await Deno.writeTextFile(path, content);
}

export async function main(root: string): Promise<number> {
  const ABBREV = Deno.env.get("CRYPTOBIB_ABBREV") ?? "abbrev1";
  const DB = Deno.env.get("CRYPTOBIB_DB") ?? "crypto_crossref.bib";
  const strict = Deno.env.get("CRYPTOBIB_STRICT") === "1";
  const dbDir = `${root}/bib/cryptobib`;
  const outFile = `${root}/bib/cryptobib.bib`;
  const dbPath = `${dbDir}/${DB}`;
  const abbrevPath = `${dbDir}/${ABBREV}.bib`;

  const cites = await collectCitations(root);
  const own = (await exists(`${root}/bib/references.bib`))
    ? parseBib(await Deno.readTextFile(`${root}/bib/references.bib`))
    : parseBib("");

  let known: (k: string) => boolean;
  if ((await exists(dbPath)) && (await exists(abbrevPath))) {
    const db = parseBib(await Deno.readTextFile(dbPath));
    const abbrev = parseBib(await Deno.readTextFile(abbrevPath));
    const keys = new Set(cites.map((c) => c.key));
    const content = [
      "% CryptoBib subset -- GENERATED by scripts/cryptobib-subset.ts, do not edit.",
      `% Source: bib/cryptobib/${DB} with ${ABBREV}.bib (https://cryptobib.di.ens.fr)`,
      "",
      buildSubset(keys, db, abbrev),
    ].join("\n");
    await writeIfChanged(outFile, content);
    const n = [...keys].filter((k) => db.entries.has(k)).length;
    log(`${n} cited CryptoBib entries -> bib/cryptobib.bib`);
    known = (k) => own.entries.has(k) || db.entries.has(k);
  } else {
    // No submodule: keep the committed subset and check against it.
    const subset = (await exists(outFile)) ? parseBib(await Deno.readTextFile(outFile)) : parseBib("");
    if (!(await exists(outFile))) {
      await Deno.writeTextFile(outFile, "% CryptoBib subset -- submodule not initialised.\n");
    }
    if (subset.entries.size > 0) {
      log("submodule bib/cryptobib not found -- keeping the committed bib/cryptobib.bib.");
      log("Run `make init` to fetch it.");
    }
    known = (k) => own.entries.has(k) || subset.entries.has(k);
  }

  const unresolved = cites.filter((c) => !known(c.key));
  if (unresolved.length > 0) {
    const where = (c: Citation) => (c.line ? `${c.file}:${c.line}` : c.file);
    log(`${unresolved.length} citation key(s) not found in bib/references.bib or CryptoBib:`);
    for (const c of unresolved) log(`  @${c.key}  (${where(c)})`);
    if (strict) return 1;
  }
  return 0;
}

if (import.meta.main) {
  const root = Deno.env.get("QUARTO_PROJECT_DIR") ?? Deno.cwd();
  Deno.exit(await main(root));
}

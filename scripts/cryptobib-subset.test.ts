/**
 * Regression tests for cryptobib-subset.ts. Run with `make test-bib`
 * (i.e. `quarto run scripts/cryptobib-subset.test.ts`); exits non-zero on failure.
 * The fixture project is tests/fixtures/project.
 */
import {
  buildSubset,
  collectCitations,
  crossrefTarget,
  latexCitations,
  macrosUsed,
  main,
  markdownCitations,
  nociteKeys,
  parseBib,
} from "./cryptobib-subset.ts";

let failures = 0;
let passed = 0;
function check(name: string, cond: boolean, detail = "") {
  if (cond) passed++;
  else {
    failures++;
    console.log(`FAIL ${name}${detail ? `\n     ${detail}` : ""}`);
  }
}
function sameSet(name: string, actual: Iterable<string>, expected: string[]) {
  const a = [...new Set(actual)].sort();
  const e = [...new Set(expected)].sort();
  check(name, JSON.stringify(a) === JSON.stringify(e), `expected ${JSON.stringify(e)}\n     got      ${JSON.stringify(a)}`);
}

const here = new URL(".", import.meta.url).pathname;
const fixture = `${here}../tests/fixtures/project`;

// --- BibTeX parsing ---------------------------------------------------------
const db = parseBib(await Deno.readTextFile(`${fixture}/bib/cryptobib/crypto_crossref.bib`));
const abbrev = parseBib(await Deno.readTextFile(`${fixture}/bib/cryptobib/abbrev1.bib`));

check("@comment content is not an entry", !db.entries.has("C:FakeInComment"));
check("paren-delimited entry", db.entries.has("C:Raw06"));
check("key with + and /", db.entries.has("C:Brace+09") && db.entries.has("EPRINT:Odd.Key/14"));
check("escaped quote inside a value does not end the entry",
  db.entries.get("C:Real01")!.text.trimEnd().endsWith("}") &&
  db.entries.get("C:Real01")!.text.includes("crossref"));
check("@string parsed", abbrev.strings.has("crypto01name") && abbrev.strings.size === 8);
sameSet("macros used by an entry", macrosUsed(db.entries.get("C01")!.text), ["crypto01name", "crypto01name", "springer", "lncs"]);
sameSet("macros used by a nested @string", macrosUsed(abbrev.strings.get("crypto01name")!), ["cryptoname"]);
check("crossref via macro", crossrefTarget(db.entries.get("C:Real01")!.text, abbrev.strings) === "C01");
check("crossref quoted", crossrefTarget(db.entries.get("EC:Text02")!.text, abbrev.strings) === "EC16");
check("no crossref", crossrefTarget(db.entries.get("EPRINT:Odd.Key/14")!.text, abbrev.strings) === null);
const own = parseBib(await Deno.readTextFile(`${fixture}/bib/references.bib`));
check("@ inside a quoted value", own.entries.has("own:Nocite") && own.entries.size === 2);

// --- Citation discovery -------------------------------------------------------
sameSet("latex \\cites with optional args",
  latexCitations("\\cites[see][p.~3]{A}{B,C} \\textcite{D} \\nocite{E}").map((k) => k.key),
  ["A", "B", "C", "D", "E"]);
sameSet("markdown: code, comments, crossrefs, escapes, emails ignored",
  markdownCitations("a [@k1] `@k2` <!-- @k3 --> @fig-a @alg-c \\@k4 x@y.org @k5.\n```\n@k6\n```\n").keys.map((k) => k.key),
  ["k1", "k5"]);
sameSet("nocite block", nociteKeys("nocite: |\n  @a, @b:c\nformat: pdf\n"), ["a", "b:c"]);
sameSet("nocite inline", nociteKeys('nocite: "@*"\n'), []);

const cites = await collectCitations(fixture);
sameSet("citations of the fixture book", cites.map((c) => c.key), [
  "C:Nocite11", "own:Nocite", // nocite
  "own:knuth", // index.qmd
  "C:Real01", "EC:Text02", "C:Brace+09", "C:Missing99", "C:Raw06", "EC:Raw07", "EC:Raw07b",
  "C:InlineRaw13", // a.qmd
  "C:Inc10", // included file
  "C:Tex17", // \input .tex, comment line skipped
  "EPRINT:Odd.Key/14", // appendix
]);
const missing = cites.find((c) => c.key === "C:Missing99");
check("line number of a citation", missing?.file === "chapters/a.qmd" && missing?.line === 7,
  JSON.stringify(missing));

// --- Subset -------------------------------------------------------------------
const subset = buildSubset(cites.map((c) => c.key), db, abbrev);
const sub = parseBib(subset);
sameSet("entries in the subset", sub.entries.keys(), [
  "C:Real01", "EC:Text02", "C:Brace+09", "EPRINT:Odd.Key/14", "C:Raw06", "EC:Raw07", "EC:Raw07b",
  "C:Inc10", "C:Nocite11", "C:InlineRaw13", "C:Tex17", "C01", "EC16",
]);
sameSet("@strings in the subset", sub.strings.keys(), [
  "lncs", "springer", "cryptoname", "crypto01name", "crypto01", "ec16name", "ec16",
]);
// every macro is defined before it is used, parents come after children
const pos = (s: string) => subset.indexOf(s);
check("nested @string defined before use", pos("@string{cryptoname") < pos("@string{crypto01name"));
check("@strings before entries", pos("@string{ec16 ") < pos("@InProceedings{C:Real01"));
check("crossref parents after their children", pos("@Proceedings{C01") > pos("@InProceedings{C:Tex17"));
check("subset is deterministic", subset === buildSubset([...cites.map((c) => c.key)].reverse(), db, abbrev));

// --- End to end ---------------------------------------------------------------
const tmp = await Deno.makeTempDir();
const copy = async (from: string, to: string) => {
  for await (const e of Deno.readDir(from)) {
    if (e.isDirectory) {
      await Deno.mkdir(`${to}/${e.name}`, { recursive: true });
      await copy(`${from}/${e.name}`, `${to}/${e.name}`);
    } else await Deno.copyFile(`${from}/${e.name}`, `${to}/${e.name}`);
  }
};
await copy(fixture, tmp);
Deno.env.set("CRYPTOBIB_STRICT", "1");
check("strict mode fails on unresolved keys", (await main(tmp)) === 1);
Deno.env.delete("CRYPTOBIB_STRICT");
check("normal mode succeeds", (await main(tmp)) === 0);
const written = await Deno.readTextFile(`${tmp}/bib/cryptobib.bib`);
check("bib/cryptobib.bib written", written.includes("@InProceedings{C:Tex17") && !written.includes("C:Orphan15"));
await Deno.remove(`${tmp}/bib/cryptobib`, { recursive: true });
check("without submodule the committed subset is kept", (await main(tmp)) === 0 &&
  (await Deno.readTextFile(`${tmp}/bib/cryptobib.bib`)) === written);
await Deno.remove(tmp, { recursive: true });

console.log(`\n${passed} passed, ${failures} failed`);
Deno.exit(failures === 0 ? 0 : 1);

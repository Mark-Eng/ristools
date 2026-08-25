# OpenAlex reading, and `write_ris()`'s tag whitelist

Maintainer note, not user documentation. Written while adding both in 0.4.0,
for whoever changes them next. It records the decisions the code cannot state
for itself, and the measurements behind them.

## Why this is a separate reader, not a wrapper

`openalexR::oa2df()` is the reference implementation for OpenAlex → data frame,
and the obvious plan was to call it and flatten its output. That does not work,
and the reason is worth keeping.

`works2df()` builds each record in one pass. Fields typed `"rbind_df"` in its
`works_process` table become nested tibbles inside that pass —
`concepts`, `keywords`, `sustainable_development_goals` — while `authorships`
goes through `process_paper_authors()` and `topics` through `process_topics()`.
There is no later flattening step to hook into, and by the time you have the
tibble, the per-record loop that had the values as plain character vectors is
over.

Flattening afterwards is possible but strictly worse: you pay `rbind.data.frame`
per record to build a tibble you immediately tear apart, and you inherit its
empty-value shapes (below) rather than choosing your own. So `oa2risdf()` here
reads the parsed JSON directly. It is a sibling of `openalexR::oa2df()`, not a
layer on it — the same relationship `parse_ris_raw()` has to the semantic
parser described in `reintroducing-semantic-fields.md`.

**The consequence to keep in mind:** the two will drift as OpenAlex changes.
`oa_columns()` is the list to extend, and `tests/testthat/fixtures/openalex_works.json`
is where a new shape gets pinned.

## Four different empty shapes, measured

The single most useful thing recorded here. `openalexR::oa2df()` represents "the
array was empty" four different ways depending on the field, verified by running
it on a two-record fixture:

| Field | Value when the OpenAlex array is `[]` |
|---|---|
| `authorships` | `data.frame` with **0 rows and 0 columns** |
| `topics` | `tbl_df` with 0 rows and 0 columns |
| `concepts`, `keywords`, `sustainable_development_goals` | scalar logical `NA` |
| `referenced_works` | scalar logical `NA` |

The split comes from `subs_na()`: it returns a bare `NA` when `length(x) == 0`,
so a field routed through it gets `NA`, while `process_paper_authors()` and
`process_topics()` reach `do.call(rbind.data.frame, list())` and get a 0×0
frame instead.

Reading the JSON directly sidesteps all four, but any code that *does* consume
`openalexR` output has to handle every one. `oa_names_from()` and friends here
are written against `NULL` and zero length only, which is all raw JSON produces.

## Why `topic_levels` is on `oa2risdf()` and not `oa2ristags()`

Each entry in a work's `topics` array carries a `subfield`, `field` and `domain`
sub-object beside its own id and name. `openalexR` unrolls that into a long
tibble with a `type` column (`topic`/`subfield`/`field`/`domain`), 4 rows per
topic.

The filter has to be applied while that structure exists. Once the column is
`"Scientometrics and Bibliometrics Research | Library and Information Sciences"`
there is nothing left saying which level each name came from, so
`oa2ristags()` — which only ever sees the collapsed frame — cannot do it.

**This is the one place `oa2risdf()` output diverges from OpenAlex semantics by
default**: its `topics` column is already topic+subfield only. That is why the
argument exists and is documented rather than being a silent choice. Pass
`topic_levels = NULL` for all four.

## `oa2ristags()` is the implementation; `ris_tags =` is an entry point

`oa2risdf(ris_tags = TRUE)` calls `oa2ristags()` as its last line and does nothing
else. There is one code path, so the two cannot disagree. The test that pins it:

```r
expect_identical(oa2risdf(x, ris_tags = TRUE), oa2ristags(oa2risdf(x)))
```

Keep that test if the argument list changes — it is the only thing stopping the
argument growing behaviour the standalone function lacks.

`oa2ristags()` is deliberately **not** a pure rename. Five mappings rewrite
values (`TY` recode, two URL strips, two prefixes) and author inversion rewrites
a sixth. All six are RIS conventions, meaningless outside a RIS file, so they
belong with the renaming rather than in `oa2risdf()`. The cost is that the function
is not idempotent by construction, which is why it carries an explicit guard:
if no OpenAlex column names are present but RIS tags are, it returns unchanged
with a message.

## Prefixes label each value, not the field

`write_ris()` writes one line per value. A field labelled once produces:

```
U3  - SDGs: Quality education
U3  - Industry, innovation and infrastructure
```

— the second line silently unlabelled. `oa_add_prefix()` therefore splits on the
delimiter and labels each value.

The alternative considered was joining SDG values with a delimiter
`write_ris()` does not split on, keeping them one line. Rejected: the package's
central invariant is that `ris_sep()` is the *only* delimiter and every field
can be split on it unconditionally (see `?ris_sep`). A second delimiter for one
field breaks that, and with it the reversibility the package exists for.

## `VL`, not `VO`

The initial mapping specified `volume` → `VO`. In the RIS specification `VL` is
"Volume number" and `VO` is "Published Standard number"; `VO` in a volume field
is not read as a volume by Zotero or EndNote. `VL` also matches what
`ris_tag_lookup()` and `ris_write_tags()` already use and is already in the
canonical tag order, so a file written from OpenAlex reads back through
`read_ris()` with the volume intact. Both tags are on the whitelist; only the
mapping chose.

## The whitelist runs *after* the tag mapping

The rule as first stated was "check each column name against a whitelist of
valid RIS tags, drop what does not match". Applied to raw column names that is
destructive, and it is worth being explicit about why, because the literal
reading looks right:

- a BibTeX read produces `author`, `title`, `year` — field names, not tags
- so does any revtools-era data frame
- so does the example in `write_ris()`'s own roxygen

All three would have been dropped wholesale. `resolve_ris_tags()` therefore
resolves first (tag_map → dialect map → the name itself) and the whitelist only
gates that last step. Existing behaviour for named columns is unchanged, which
the 230 tests predating 0.4.0 confirm.

**If you tighten this further, run the full suite first.** `test-bib.R` and
`test-roundtrip.R` are the ones that catch it.

## Two traps in the old pass-through check

`as_ris_tag()` used to accept anything matching `"^[A-Z][A-Z0-9]{1,3}$"`.
Verified against the 0.3.0 code:

- **`ER` passed.** A column named `ER` wrote `ER  -` as a data line. Every
  reader — `read_ris()` included — finds record boundaries by that tag, so one
  such column splits every record in two. `ER` is excluded from
  `ris_tag_whitelist()` for this reason and must stay excluded.
- **Any 2–4 character uppercase token passed.** `TITL` wrote `TITL  - x`;
  `ABCD` wrote `ABCD  - y`. Neither is a RIS tag and no reader does anything
  useful with them.

`read_ris()`'s tag pattern only ever matches **two** characters
(`^[[:upper:]][[:upper:][:digit:]]  - `), so a name longer than two characters
cannot have come from a file this package read. `test-write-ris-whitelist.R`
asserts every whitelisted tag is two characters, which keeps the reader and
writer agreeing about what a tag is.

## The drop has to happen before `prepare_entries()`

`prepare_entries()` coerces every column with `as.character(x[[cl]][i])`. Two
things go wrong if an unwritable column survives that long:

1. A list column is deparsed into the file as
   `list(id = c("https://openalex.org/..."), display_name = c("Science Mapping"))`.
2. A list column holding a scalar `NA` becomes the character string `"NA"`,
   which `clean_entry()`'s `is.na()` filter cannot see — it is a real string by
   then — so the file gets `KW  - NA`.

Both were reproduced against 0.3.0 by feeding it `openalexR::oa2df()` output
directly. Dropping in `write_ris()` before that call means a column that cannot
be written correctly cannot be mangled into the file instead. **Keep the drop
ahead of `prepare_entries()`** if that function is ever reordered.

### The name check is not sufficient on its own

Worth knowing, because it was missed on the first pass and only turned up when
`openalexR::oa2df()` output was run through the finished writer as a check.

Dropping by name handles `authorships`, `concepts`, `topics` and
`sustainable_development_goals`, none of which is in the tag map. It does
**not** handle `keywords`: `ris_write_tags()` maps `keywords` to `KW`, so the
column resolves correctly and then deparses, because the name was never the
problem. A second pass drops any column that is not atomic, whatever its name.

The general shape of the rule: *a valid tag says nothing about the contents.*
Anything added to the tag map needs the same question asked of it.

## Author inversion: what was decided and why

Inverting `"Massimo Aria"` to `"Aria, Massimo"` was requested after the risk was
flagged, so it is on by default with `invert_authors = FALSE` as the escape.
The rules are in `?oa2ristags`; the reasoning behind the one non-obvious rule:

**Particles are absorbed only when lower case in the original.** This is
BibTeX's rule for finding the "von" part of a name, and it is a real
discriminator: `"van der Berg"` is a surname, `"Della"` is a given name. A
case-insensitive list would swallow `"Della Rosa"` into a single surname.
Title-cased Dutch particles (`"Van Der Berg"`, common in English-language
sources) are the known cost — they come out as `"Berg, Van Der"`.

**What no rule can fix:** OpenAlex stores some `display_name`s family-name
first, common for Chinese and Korean authors. `"Wang Xiaoming"` is
indistinguishable from a given-name-first name, and is inverted wrongly. There
is no signal in the record to separate the two — `author_position`, `orcid` and
the raw affiliation strings all say nothing about name order. If this matters
for a given corpus, `invert_authors = FALSE` is the answer, not a longer
heuristic.

## Deliberately not done

- **`referenced_works` and `related_works` have no RIS tag** and are left as
  delimited strings for `write_ris()` to drop. They are useful for citation
  chasing in R, which is why they are carried at all.
- **`UR` is unmapped.** `oa_url`, `landing_page_url`, `pdf_url` and `doi` are
  all plausible sources for it and the choice is corpus-specific, so none was
  wired up. `tag_map = c(oa_url = "UR")` does it per call if wanted.
- **`DA` is written as OpenAlex supplies it**, `"2017-11-01"`, not the
  `"2017/11/01"` form some RIS writers use. Decided deliberately; changing it
  is a one-line `gsub` in `oa2ristags()` plus a test.
- **Only works are handled.** `oa_check_works()` errors on anything else rather
  than returning a frame of `NA`s. Other entities have almost no RIS meaning;
  `openalexR::oa2df()` covers them.

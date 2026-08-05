# Reintroducing semantic field names, Medline and Web of Science

Maintainer note, not user documentation. Written while removing these features
in 0.3.0, for whoever brings them back.

0.3.0 removed the semantic renaming layer (`read_ris(rename_columns = TRUE)`),
Medline and Web of Science reading, CSV reading, and record labels, to make the
package a focused RIS reader/writer. The code is in git history; what follows
is the part history does not record — why each piece worked the way it did,
which parts were already broken, and where the traps are.

## Recovering the code

The last commit containing `parse_ris_tags()`, `read_medline()`,
`generate_ris_names()`, `ris_tag_pattern()`'s permissive branch and all four
lookup tables is **`9a43b7c`** ("Correct license info.") — the commit
immediately preceding the 0.3.0 refactor on `main`.

```sh
git show 9a43b7c:R/read-ris.R   > read-ris-0.2.0.R
git show 9a43b7c:R/tag-lookup.R > tag-lookup-0.2.0.R
git show 9a43b7c:tests/testthat/test-raw-tag-columns.R
git show 9a43b7c:tests/testthat/test-tag-lookup.R
```

Line references below are to those files as of `9a43b7c`.

## The central design constraint: an additional path, never a transform

This is the most important thing on this page. When 0.2.0 introduced raw-tag
output, the obvious implementation — parse semantically, then rename the
columns back to their tags — was tried and rejected as **impossible, not merely
awkward**. The semantic functions do not relabel fields; they *merge* them, and
several merges are one-way:

- **`title`** (`parse_ris_tags()` ~797-807): when a record has two title tags
  with different content, they are `paste(collapse = " ")`d into one string.
  Nothing records which words came from `TI` and which from `T1`.
- **`pages`** (~836-852): `SP`/`BP` and `EP` become one string, `"419-41"`. An
  end page with no start page becomes `"-218"` — the leading dash is the only
  thing distinguishing it from a start page of 218.
- **`journal`** (~813-824): seven tags map to `journal`. The first to appear
  supplies it; the others are kept under their own tag names. Recoverable, but
  only because of that deliberate choice.
- **`author`** (~759-775): where several author tags are present, the *most
  frequent* wins `author` and the rest are demoted to their own tag names.
- **`keywords`**: `KW` and `DE` merge into one vector with tag identity gone.
- **`year`** (~711-756): a heuristic searches every 4-digit-looking value,
  computes what proportion of records carry one under each tag, and if any tag
  exceeds 90% it is *relabelled* `year` — even if it was already mapped to
  something else. This is why a file where >90% of start pages are 4 digits
  long could have `SP` relabelled `year`; the third condition at ~735-738
  (`x_merge$bib[check_rows] == x_merge$ris[check_rows]`) was added to stop that.

So: **any reintroduction must run alongside the raw parse, not on top of its
output.** 0.2.0 settled on two independent code paths sharing `prep_ris()`, and
that decision should stand. `parse_ris_raw()` is the raw path and is now the
only one; a semantic path should be a sibling of it.

## What `rename_columns = TRUE` guaranteed

Pin a reintroduction against these, since they were the tested contract:

| Field | Rule |
|---|---|
| `author` | most frequent of `AU`/`A1`/`A2`/`A3`/`A4`/`A5`; losers keep their own tag |
| `journal` | first present of `JO`/`T2`/`T3`/`SO`/`JT`/`JF`/`JA`; others keep their own tag |
| `pages` | `SP`/`BP` then `EP`, joined `"419-41"`; `"-218"` for end-page-only |
| `year` | reduced to the 4-digit year; a value with **no** 4-digit year is kept verbatim, not blanked |
| `title` | trailing full stop **kept** (stripping it broke titles ending `U.S.`) |
| `abstract` | absent stays absent (the old guard `length(result$abstract > 1)` is always `1`, so every record without an abstract used to gain an empty one) |
| tags with digits | `M3`, `Y2`, `U1` keep their case |

For a concrete before/after, the semantic column set for
`tests/ebsco_tests/2024-10 to 2024-12-31 (de-duped 1-163).txt` was:

```
label, type, abstract, accession, author, doi, issue, keywords, year, issn,
pages, journal, title, url, volume, DB, DP, ID, M3, N1, ST
```

against the raw column set for the same file:

```
label, TY, AB, AN, AU, DB, DO, DP, IS, KW, M3, N1, PY, SN, SP, ST, T2, TI,
UR, VL, ID
```

(0.3.0 drops the `label` column from both.)

## Medline was already dead code when it was deleted

Do not restore `read_medline()` expecting it to work. **It was unreachable on
every path**, verified by running the 0.2.0 code:

- Medline was detected by `any(z_dframe$ris == "PMID")` (0.2.0 read-ris.R:215).
- But a `.nbib` file is not `.ciw`, so it got `tag_type = "ris"` and therefore
  the **strict** tag pattern: two characters, then exactly two spaces and a
  hyphen.
- `PMID` is four characters. The strict pattern cannot match it, so `PMID`
  never became a field and `is_medline` was never `TRUE`.
- Worse, `prep_ris()`'s `start_tag` election (which picks the modal opening tag
  and slices each record from it to `ER`) then discarded the `PMID` line
  altogether. A real `.nbib` record came out as `ZZ, TI, AB, AU, DP`.

`read_medline()` and `ris_tag_lookup("medline")` therefore had **zero test
coverage and zero real exercise**. Treat the deleted function as a sketch of
intent, not a working implementation.

Real `.nbib` support needs a tag pattern scoped to that format — see the next
section for why that is delicate. Note also that `.nbib` permits `PMID-` with
one space or none, so the separator cannot be assumed to be two spaces.

## Why the permissive tag pattern is dangerous

`ris_tag_pattern()` returned two regexes:

```r
# tag_type == "ris" -- strict
"^[[:upper:]][[:upper:][:digit:]]  - |^[[:upper:]][[:upper:][:digit:]]  -$"

# anything else (i.e. "wos") -- permissive
"^([[:upper:]]{2,4}|[[:upper:]]{1}[[:digit:]]{1})\\s{0,}-{0,2}\\s{0,}"
```

The permissive one is what WoS `.ciw` needs, because its tags are a bare two
characters and a single space (`AU Smith, J`). **Applied to a RIS file it
causes silent data loss**, which was the 0.1.2 bug: EBSCO breaks a multi-value
`KW` field across lines *without repeating the tag*, so

```
KW  - Carbon emissions
E7 economies
EKC
```

parsed `E7 economies` as tag `E7` with text `economies` — the keyword lost its
first word, a bogus `E7` field appeared, and the fill-forward then attributed
following lines to `E7`. A whole-line match like `EKC` left no text at all and
was dropped by the empty-row filter.

If a per-format pattern comes back, **select it by format and never let the
permissive form touch `.ris`**. `tests/testthat/test-tag-regex.R` survives
0.3.0 and still pins this behaviour — run it against any change here.

## Labels: do not reinstate the two-pass parse

0.3.0 removed record labels entirely. If they return, note that
`parse_ris_raw()` used to name records by calling
`generate_ris_names(parse_ris_tags(x, tag_type))` — running a full 199-line
semantic parse purely to produce a label string and discarding everything else.
That is not necessary. A fixed tag-preference list reproduced **2185 of 2186**
real EBSCO labels exactly:

```r
author  <- c("AU", "A1", "A2", "A3", "A4", "A5", "AF")
year    <- c("PY", "Y1", "DA")
journal <- c("JF", "JO", "JA", "J1", "J2", "JT", "SO", "T2", "T3")
# take the first tag in each list that the record actually has
```

Two findings that are easy to get wrong:

1. **These lists must not be derived from `ris_tag_lookup()`'s order.** That
   table lists `T2` and `T3` *before* `JF`/`JO`, because its order serves
   `write_ris()`'s canonical field ordering, not label quality. Using it labels
   a journal article after its series title.
2. **The one differing record was an improvement.** A record with `A2`/`A4` but
   no `AU`/`A1` was labelled with a bare year (`2025`) under the semantic path,
   because the frequency election found no winning author tag and emitted no
   `author` field at all. The preference list gives `Song_2025`.

### The `min()` / `pmin()` trap — measure before "fixing"

`generate_ris_names()` abbreviated the journal with:

```r
substr(journal_info, 1, min(nchar(journal_info), 4))
```

`min()` over the whole word vector collapses to a **scalar**, so every word is
truncated to the *shortest* word's length: `"Journal of Things"` → `JoofTh`,
not `JourofThin`. This looks unambiguously like a `pmin()` typo. It was
measured across all 2186 EBSCO records before 0.3.0, and "fixing" it is
**worse** on every axis:

| | `min()` (as shipped) | `pmin()` ("fixed") |
|---|---|---|
| mean label length | 18.7 chars | 25.3 chars |
| max label length | 55 chars | 92 chars |
| unique labels | 1831 / 2186 | 1755 / 2186 |
| `Corporate Social Responsibility & Environmental Management` | `CSR&EM` | `CorpSociResp&EnviMana` |

The accident produces a compact, acronym-like abbreviation that is *better* for
a label and collides *less often*. **Do not change it without re-running that
measurement.**

## Tests to recover

The deleted tests are the executable specification. From
`tests/testthat/test-raw-tag-columns.R` at `v0.2.0`:

- "rename_columns = TRUE reproduces today's semantic output"
- "rename_columns = TRUE on a sparse record matches pre-0.2.0 behaviour"
- "record labels are the same regardless of rename_columns"
- "a Web of Science file with rename_columns = TRUE matches prior behaviour"
- "BibTeX output is unaffected by rename_columns"
- "a rename_columns = TRUE read round-trips through write_ris with values intact"

From `tests/testthat/test-edge-cases.R` at `v0.2.0` (these assert the merge
itself, so they only make sense with semantic fields present):

- "an end page with no start page is distinguishable" (`pages == "-218"`)
- "an end-page-only value round-trips"
- "a single-value page field is kept" (`pages == "77"`)
- "where several tags map to journal, extras keep their own tag"

`tests/testthat/test-tag-lookup.R` at `v0.2.0` pinned all four tables by exact
dimensions — `ris` 42x3, `ris_write` 25x2, `medline` 67x2, `wos` 82x2 — plus
the `ED` duplication and the two upstream typos. Recover it wholesale if the
tables come back.

## The inherited warts, and a chance to decide them deliberately

These came from revtools 0.4.1 and were preserved verbatim so that existing
files would keep parsing identically. A reintroduction should *decide* them
rather than re-inherit them:

- **`ED` maps to both `editor` and `edition`** in the `ris` table (verified
  still present after 0.3.0: `ED`→`editor` at order 21, `ED`→`edition` at order
  22). The `ris` table survives as reference data, so this duplication is still
  in the package — but it is now *inert*, because nothing merges tags to fields
  any more. It only mattered when `parse_ris_tags()` performed a many-to-many
  merge, which read every `ED` line in a file as **two** fields. If semantic
  parsing returns, this becomes live again and needs a decision about which
  meaning applies to a given source.
- **`ris_tag_lookup("medline")` maps `PMC` to `pubmed_central_identitfier`** —
  a typo, preserved because correcting it would orphan any code keying on it.
- **`ris_tag_lookup("wos")` maps `WC` to `wos_cagegories`** — likewise.

## Other things 0.3.0 removed that are less worth restoring

- **`read_ris_csv()` / `clean_author_delimiters()`.** CSV is not a
  bibliographic format, and the function's value-add was synthesising the
  `label` column (now gone) plus *guessing* an author delimiter from
  column-wide heuristics — the kind of silent, irreversible inference this
  package exists to avoid. It had zero test coverage.
- **`detect_delimiter()`'s `"character"` and `"space"` branches**, for records
  separated by a rule of repeated characters or by blank lines instead of `ER`.
  Unreachable for any file containing `ER`, untested, and the
  repeated-character test was itself broken: `length(a > 6)` is the line's
  character count, not a repeat count, so any file reaching that branch was
  parsed into something arbitrary rather than rejected. 0.3.0 replaced the
  whole function with an explicit error. If a real RIS-family format without
  `ER` turns up, add a guard for it specifically.
- **`ris_to_df()`'s `col_n < 3` column reordering.** It pushed short (raw-tag)
  names behind long (semantic) ones, for the mixed output `parse_ris_tags()`
  produced. It also actively *scrambled* order whenever a field name was 3+
  characters: `list(TY, ABCD, T1)` came back as `ABCD, TY, T1`. If semantic
  names return and column ordering matters, solve it explicitly rather than by
  name length.

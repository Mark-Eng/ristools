# ristools

Read and write RIS, BibTeX, Medline and Web of Science bibliographic files in
R, without the data loss that affects several existing implementations.

Depends only on base R.

## Installation

```r
# private repo: needs a GitHub PAT with repo scope
remotes::install_github("Mark-Eng/ristools")
```

## Usage

```r
library(ristools)

# read a file; multi-value fields are joined with " | "
df <- read_ris("econlit_export.ris")
df$author
#> [1] "Smith, John A. | Jones and Partners, Mary B."

# or keep one list element per record, with proper vectors
recs <- read_ris("econlit_export.ris", return_df = FALSE)
recs[[1]]$author
#> [1] "Smith, John A."             "Jones and Partners, Mary B."

# write back out; an Ovid-style export round-trips unchanged
write_ris(df, "out.ris")

# convert between the two representations
df    <- ris_to_df(recs)
recs  <- df_to_ris(df)

# split a large export into importable chunks
split_ris_file("huge_export.ris", "chunks/", set_size = 10000)
```

Reading several files at once combines them and records the source of each
record in a `filename` column:

```r
files <- list.files("exports", pattern = "\\.ris$", full.names = TRUE)
df <- read_ris(files)
```

## Why this exists

These functions began as a rewrite of
[revtools](https://revtools.net) 0.4.1's read and write path, which loses data
in ways that are hard to notice and impossible to reverse after the fact.
revtools has been unmaintained since 2019.

### The multi-value delimiter

A bibliographic record routinely holds several values in one field: authors,
keywords, JEL descriptors, ISSNs. Collapsing a record into one row of a data
frame means joining them, and the join has to be reversible.

revtools joined with `" and "`. That string occurs *inside* real values:

| Value | What `" and "` splitting does |
|---|---|
| `Jones and Partners, Mary B.` | becomes two authors |
| `Journal of Economics and Statistics` | becomes two journals |
| `Climate; Natural Disasters and Their Management; Global Warming [Q54]` | becomes two descriptors |

`ristools` joins with `" | "`, which cannot occur in bibliographic text. That
makes the join reversible for *every* field, so no field needs special
handling and `ris_to_df()` / `df_to_ris()` are exact inverses.

The delimiter is available as `ris_sep()`. Always use it with `fixed = TRUE`:
`|` is a regex metacharacter.

### Other losses fixed

| Field | Problem in revtools 0.4.1 |
|---|---|
| `pages` | `SP`/`BP` and `EP` all map to `pages`, and the order came from `sort()`. A range with an abbreviated end page reversed: `419` + `41` became `41-419`. An end page with no start page was indistinguishable from a start page. |
| `title` | The trailing full stop was stripped, so titles ending `U.S.` or `D.C.` lost their last character. |
| `journal` | Seven tags map to `journal`; extras were sorted by string length and pasted into a `journal_secondary` string, losing the tag they came from. |
| `abstract` | The guard was `length(result$abstract > 1)`, which is always `1`, so *every* record without an abstract was given an empty one. |
| fields | Entry ordering used `unlist(lapply(...))`, which returned a short vector when a name did not match and silently dropped a field. |
| `year` | A value with no 4-digit year was blanked. The "which tag holds the year" heuristic could relabel an already-mapped tag (e.g. `SP`) as `year`. |
| names | Tags containing a digit were lower-cased, so `M3`/`Y2` became `m3`/`y2` and were then dropped on write. |

On write, tags were built with `gsub("[[:digit:]]", "", tag)`, which turned
`M3` into `M` and `Y2` into `Y` before the lookup, so those fields disappeared.
`ristools` expands repeated values with `rep(names(a), lengths(a))` instead, so
multi-value fields get one line per value and tags keep their digits.

## Notes and caveats

**`ED` is read as two fields.** The RIS tag table maps `ED` to both `editor`
and `edition`. Because the tag-to-field merge is many-to-many, every `ED` line
in a file is read as two fields. This is inherited from revtools and is
preserved deliberately so that existing files parse identically; it is pinned
by a test rather than fixed, because fixing it needs a decision about which
meaning applies to a given source.

**Two upstream typos are preserved verbatim**, for the same reason: the Medline
table maps `PMC` to `pubmed_central_identitfier` and the Web of Science table
maps `WC` to `wos_cagegories`.

**Mixing with revtools.** `ristools` does not depend on, load, or modify
revtools, and defines no S3 methods on revtools' classes. But if you pass
`ristools` output to revtools' own screening functions, note that
`format_citation()` and `screen_duplicates()`/`screen_titles()` split authors
on `" and "`, so a `" | "`-joined author list renders as one long name. Convert
with `df_to_ris()` and re-join with `" and "` first if you need those
functions.

## API

| Function | Purpose |
|---|---|
| `read_ris()` | read one or more RIS/BibTeX/Medline/WoS files |
| `write_ris()` | write records as RIS or BibTeX |
| `read_ris_csv()` | read a csv-format bibliography |
| `ris_to_df()` | record list → data frame |
| `df_to_ris()` | data frame → record list |
| `ris_sep()` | the multi-value delimiter, `" \| "` |
| `ris_index()` | zero-padded record labels |
| `ris_tag_lookup()` | the tag → field mapping for a format |
| `split_ris_file()` | split a large RIS file into chunks |

## License

MIT

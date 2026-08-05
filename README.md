# ristools

A set of R tools for reading and writing bibliographic files in RIS format. Unlike existing general-purpose tools for evidence synthesis work (e.g., the `revtools` and `synthesisr` packages), `ristools` is specialised for working with RIS files. The functions in `ristools` prioritise preventing loss of information or structure when converting RIS files to dataframes and vice versa.

`ristools` draws on the [revtools](https://github.com/mjwestgate/revtools) codebase and preserves some of its functions. Thanks to Martin Westgate for developing `revtools` and making the code available.

Currently, `ristools`-specific functions are only implemented for `.ris` files. Functions for working with other bibliographic formats, including `.nbib` and `.ciw`, are currently carried over from `revtools`; full support for these file types under `ristools` is planned.

This package also includes a function to split large ris files into smaller chunks (default = 10,000 references) so they may be more easily imported to reference management/review software.

## Why this exists

These functions began as a rewrite of [revtools](https://revtools.net) 0.4.1's read and write functions, which often lose data when reading or writing bibliographic files. The changes from `revtools` to `ristools` reflect `ristools`'s intended use as a  more specialised package for working with bibliographic metadata files, without the need to perform other tasks within the evidence synthesis process. 

## Installation

```r
# private repo: needs a GitHub PAT with repo scope
remotes::install_github("Mark-Eng/ristools")
```

## Usage

```r
library(ristools)

# read a file; one column per raw tag, exactly as the file has it. 
# Multi-value fields are joined with " | "
df <- read_ris("econlit_export.ris")
df$AU
#> [1] "Smith, John A. | Jones and Partners, Mary B." or keep one 
# list element per record, with proper vectors
recs <- read_ris("econlit_export.ris", return_df = FALSE)
recs[[1]]$AU
#> [1] "Smith, John A."             "Jones and Partners, Mary B."

# rename_columns = TRUE merges tags that often "mean" the same thing 
# (e.g., "TI" and "T1") into one semantically-named field (author, title, year, ...),
# as in revtools.
df2 <- read_ris("econlit_export.ris", rename_columns = TRUE)
df2$author
#> [1] "Smith, John A. | Jones and Partners, Mary B."

write_ris(df, "out.ris")

# convert between the two representations
df    <- ris_to_df(recs)
recs  <- df_to_ris(df)

# split a large export into importable chunks
split_ris_file("huge_export.ris", "chunks/", set_size = 10000)
```

### Raw tags by default

`read_ris()` creates a dataframe that names every column after the raw tag it was read under — `AU`, `TI`, `PY`, `KW`, etc. Page numbers are preserved in separate starting page (`SP` or `BP`) and ending page (`EP`) columns. This keeps the output as close as possible to the input file, so a record can be read, inspected as a table, and written back out with nothing lost or relabelled along the way. A tag repeated within one record (two `AU` lines, several `KW` lines) becomes a vector under that one tag.

Because the tag used for a given concept can differ by source, column names follow the input file rather than fixed schema: the dateframe column with author names may be named `A1` or `AU`, depending on the tag used in the input file. Thus, the default column naming behaviour is most appropriate when working with a single RIS file or a series of RIS files all from the same platform/database.

`rename_columns = TRUE` restores the semantic naming used by `revtools`: `author` (from whichever of `AU`/`A1`/`A2`/… is most frequent, with any other author-mapped tag kept under its own name), `title`, `year`, `journal` (the first of `JO`/`T2`/`T3`/`SO`/`JT`/`JF`/`JA` found, others again kept separately), and `pages` (`SP`/`BP` merged with `EP` into one `"419-41"`-style string). This may be useful when combining RIS files from several platforms/databases into a single dataframe.

Reading several files at once combines them and records the source of each record in a `filename` column:

```r
files <- list.files("exports", pattern = "\\.ris$", full.names = TRUE)
df <- read_ris(files)
```

**Only RIS-form tags are recognised in RIS files.** A tag has to be a capital followed by a capital or a digit, then two spaces and a hyphen. A line that does not match is treated as a continuation of the field above it, which is what makes wrapped keyword blocks parse correctly. Web of Science `.ciw` files use a different form (`AU Smith, J`) and are matched by a separate, permissive pattern, chosen by file type. `.nbib`/PubMed exports, whose tags look like `PMID- 29939999` and may replace a space with another character, are a planned enhancement: they currently fall back to the permissive pattern.

### The multi-value delimiter

Depending on the source, bibliographic records may hold several values in one field (e.g., authors, keywords, or subject headings). Collapsing a record into one row of a data frame means joining them, and the join has to be reversible to preserve all information when writing back to a RIS file. `revtools` joins multiple values with `" and "`, which may occur inside real values:

| Value | Result of splitting with `" and "`  |
|---|---|
| `Jones and Partners, Mary B.` | becomes two authors |
| `Journal of Economics and Statistics` | becomes two journals |
| `International Trade and Finance [B17]` | becomes two *Journal of Economic Literature* (JEL) descriptor codes |

`ristools` joins with `" | "`, which generally does not occur in bibliographic files. That makes the join reversible for every field, allowing `ris_to_df()` and `df_to_ris()` to be exact inverses.

You may select a different delimiter with `delimiter`, e.g.,
`read_ris(filename, delimiter = ";")`

### Other losses addressed

| Field | `revtools` behaviour |
|---|---|
| `pages` | `SP`/`BP` and `EP` all map to `pages`, and the order came from `sort()`. A range with an abbreviated end page reversed: `419` + `41` became `41-419`. An end page with no start page was indistinguishable from a start page. |
| `title` | The trailing full stop was stripped, so titles ending `U.S.` or `D.C.` lost their last character. |
| `journal` | Seven tags map to `journal`; extras were sorted by string length and pasted into a `journal_secondary` string, losing the tag they came from. |
| `abstract` | The guard was `length(result$abstract > 1)`, which is always `1`, so *every* record without an abstract was given an empty one. |
| fields | Entry ordering used `unlist(lapply(...))`, which returned a short vector when a name did not match and silently dropped a field. |
| `year` | A value with no 4-digit year was blanked. The "which tag holds the year" heuristic could relabel an already-mapped tag (e.g. `SP`) as `year`. |
| names | Tags containing a digit were lower-cased, so `M3`/`Y2` became `m3`/`y2` and were then dropped on write. |

On write, tags were built with `gsub("[[:digit:]]", "", tag)`, which turned `M3` into `M` and `Y2` into `Y` before the lookup, so those fields disappeared. `ristools` expands repeated values with `rep(names(a), lengths(a))` instead, so multi-value fields get one line per value and tags keep their digits.

### Byte order marks and encoding

Two further `revtools` features made every EBSCO file either unreadable or silently corrupt. Both are fixed here.

**A leading byte order mark broke the read entirely.** A BOM is three bytes (`EF BB BF`) before the first tag. `revtools` marks all imported text `latin1`, which turns those bytes into three visible characters, so the first tag stops matching the tag pattern under the `C` locale the reader sets. That record loses its opening tag, the parser then finds one fewer record start than record end, and the read fails with:

```
Error in data.frame(...) : arguments imply differing number of rows: 162, 163
```

**Non-ASCII text was mojibaked.** Because the encoding was hardcoded to `latin1` rather than detected, every multi-byte character in a UTF-8 file was reinterpreted byte by byte:

| Raw file (UTF-8) | `revtools` 0.4.1 | `ristools` |
|---|---|---|
| `socio‐economic` | `socioâ€economic` | `socio‐economic` |
| `Bandhan’s` | `Bandhanâ€™s` | `Bandhan’s` |
| `“Graduation”` | `â€œGraduationâ€` | `“Graduation”` |
| `Parienté` | `Parient<c3><a9>` → `Parient` | `Parienté` |

### Keywords wrapped across lines

Some files exported from EBSCO break a multi-value `KW` field across several lines *without repeating the tag*:

```
KW  - Carbon emissions
E7 economies
EKC
GHG
Non-renewable
M3  - Article
```

The tag is filled forward across those lines. 

### Splitting a large file

Some reference management and review platforms cap the number of records they will accept per import. `split_ris_file()` breaks a large export into fixed-size chunks:

```r
split_ris_file("huge_export.ris", "chunks/", set_size = 10000)
#> Wrote huge_export (1-10,000).ris
#> Wrote huge_export (10,001-20,000).ris
#> Wrote huge_export (20,001-23,412).ris
```

The output directory is created if it does not exist, and the paths written are returned invisibly, so they can be fed straight back to read_ris():
`paths <- split_ris_file("huge_export.ris", "chunks/", set_size = 5000)`
`df <- read_ris(paths)`

Chunks are named after the input file with the record range appended. Any parenthesised suffix already on the input name is dropped first, so re-splitting an already-split file gives export (1-500).ris rather than export (1-1,000) (1-500).ris.

Splitting works at the text level, not by parsing. Records are delimited by lines starting TY  -  and ER  -, and every line between them is copied verbatim. No field is read, mapped, or rewritten, so splitting cannot alter or lose data even in a file read_ris() would struggle with. The function stops rather than guessing if the file has no TY  -  lines, or if the TY/ER counts disagree — the latter usually means a truncated download or a record missing its terminator.

## Notes and caveats

**`ED` is read as two fields.** The RIS tag table maps `ED` to both `editor` and `edition`. Because the tag-to-field merge is many-to-many, every `ED` line in a file is read as two fields. This is inherited from `revtools` and is preserved deliberately so that existing files parse identically; it is pinned by a test rather than fixed, because fixing it needs a decision about which meaning applies to a given source.

**Two upstream typos are preserved verbatim**, for the same reason: the Medline table maps `PMC` to `pubmed_central_identitfier` and the Web of Science table maps `WC` to `wos_cagegories`.


**Mixing with revtools.** `ristools` does not depend on, load, or modify revtools, and defines no S3 methods on revtools' classes. But if you pass `ristools` output to revtools' own screening functions, note that `format_citation()` and  screen_duplicates()`/`screen_titles()` split authors on `" and "`, so a `" | "`-joined author list renders as one long name. Convert with `df_to_ris()` and re-join with `" and "` first if you need those functions.

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

GPL-3

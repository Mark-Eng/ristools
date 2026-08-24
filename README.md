# ristools

A set of R tools for reading and writing bibliographic files in RIS format, and for turning OpenAlex search results into them. Unlike general-purpose tools for evidence synthesis work (e.g., the `revtools` and `synthesisr` packages), `ristools` is specialised for RIS files, and prioritises preventing loss of information or structure when converting RIS files to dataframes and back.

Reading a RIS file gives you a dataframe whose columns are the file's own tags — `TY`, `AU`, `TI`, `KW` — with nothing renamed, merged or reordered. So you can read a file, inspect and edit it as a table, and write it back out unchanged.

The package also includes a function to split large RIS files into smaller chunks (default = 10,000 references) so they may be more easily imported to reference management/review software.

`ristools` draws on the [revtools](https://github.com/mjwestgate/revtools) codebase. Thanks to Martin Westgate for developing `revtools` and making the code available.

## Scope

`ristools` reads and writes `.ris` files, reads and writes BibTeX, and reads OpenAlex works from JSON. Web of Science (`.ciw`) and PubMed (`.nbib`) exports tag their lines differently and are **not** supported: they are rejected with a message naming the format, rather than being misparsed into something that looks plausible. Support for them may be added later, with a tag pattern specific to each.

## Installation

```r
# private repo: needs a GitHub PAT with repo scope
remotes::install_github("Mark-Eng/ristools")
```

## Usage

```r
library(ristools)

# one column per tag in the file. Multi-value fields are joined with " | "
df <- read_ris("econlit_export.ris")
colnames(df)
#> [1] "TY" "AU" "TI" "PY" "JO" "SP" "EP" "KW" "M3" "SN" "DO"
df$AU
#> [1] "Smith, John A. | Jones and Partners, Mary B."

# or keep one list element per record, with proper vectors
recs <- read_ris("econlit_export.ris", return_df = FALSE)
recs[[1]]$AU
#> [1] "Smith, John A."             "Jones and Partners, Mary B."

write_ris(df, "out.ris")

# convert between the two representations
df    <- ris_to_df(recs)
recs  <- df_to_ris(df)

# what does a given tag conventionally hold?
tags <- ris_tag_lookup()
tags[tags$ris == "M3", ]

# split a large export into importable chunks
split_ris_file("huge_export.ris", "chunks/", set_size = 10000)

# OpenAlex works -> dataframe with RIS tags for column names -> .ris
oa <- oa2df("openalex_search.json", ris_tags = TRUE)
write_ris(oa, "openalex.ris")
```

### Columns are the file's own tags

Every column is named after the tag it was read under — `AU`, `TI`, `PY`, `KW` — and tags that conventionally mean the same thing are **not** combined. A file using both `KW` and `DE` gets a column for each; start and end pages stay in separate `SP` (or `BP`) and `EP` columns. A tag repeated within one record (two `AU` lines, several `KW` lines) becomes a vector under that one tag, joined with `" | "` in the dataframe.

Nothing is invented and nothing is dropped, which is what makes the read → edit → write cycle safe.

The trade-off is that column names follow the input file rather than a fixed schema: authors arrive as `A1` in an Ovid export but `AU` in an EconLit one. So this suits working with one file, or several from the same platform. Combining files from different platforms means reconciling the tags yourself — `ris_tag_lookup()` tells you what each one conventionally holds.

Reading several files at once combines them and records the source of each record in a `filename` column:

```r
files <- list.files("exports", pattern = "\\.ris$", full.names = TRUE)
df <- read_ris(files)
df$filename
#> [1] "export_2024.ris" "export_2024.ris" "export_2025.ris" ...

# full paths instead, e.g. when the same file name occurs in several folders
df <- read_ris(files, full_path = TRUE)
```

There is no `label` column: the dataframe holds your data and nothing else. Record names are available from the list form, via `names(read_ris(f, return_df = FALSE))`.

**Only RIS-form tags are recognised.** A tag has to be a capital followed by a capital or a digit, then two spaces and a hyphen. A line that does not match is treated as a continuation of the field above it, which is what makes wrapped keyword blocks parse correctly. Records must end with `ER`; a file without one is rejected rather than guessed at.

### The multi-value delimiter

Depending on the source, bibliographic records may hold several values in one field (e.g., authors, keywords, or subject headings). Collapsing a record into one row of a dataframe means joining them, and the join has to be reversible to preserve all information when writing back to a RIS file.

`" and "` is the conventional choice, but it occurs inside real values, so splitting on it corrupts them:

| Value | Result of splitting with `" and "`  |
|---|---|
| `Jones and Partners, Mary B.` | becomes two authors |
| `Journal of Economics and Statistics` | becomes two journals |
| `International Trade and Finance [B17]` | becomes two *Journal of Economic Literature* (JEL) descriptor codes |

`ristools` joins with `" | "`, which generally does not occur in bibliographic files. That makes the join reversible for every field, allowing `ris_to_df()` and `df_to_ris()` to be exact inverses.

You may select a different delimiter with `delimiter`, e.g.,
`read_ris(filename, delimiter = ";")` — though a delimiter that appears inside your data will not split back correctly.

### Fidelity details

Small things that are easy to get wrong, and that this package gets right:

| | |
|---|---|
| Page ranges | `SP`/`BP` and `EP` stay in their own columns, so an abbreviated end page (`419`–`41`) cannot be reordered, and an end page with no start page is never mistaken for a start page. |
| Titles | Trailing punctuation is kept, so a title ending `U.S.` or `D.C.` keeps its last character. |
| Absent fields | A record without an abstract gets no abstract column, rather than an empty one. |
| Tags with digits | `M3`, `Y2` and `U1` keep their case and their digits, on read and on write. |
| Field order | Columns follow the order fields first appear; nothing is silently dropped or moved. |
| Multi-value writes | A field holding several values becomes one line per value, repeating the tag. |

### Byte order marks and encoding

Both of these made every EBSCO export either unreadable or silently corrupt under `revtools`, and both are handled here.

**A leading byte order mark.** A BOM is three bytes (`EF BB BF`) before the first tag. Marking imported text `latin1` turns them into three visible characters, so the first tag stops matching under the `C` locale the reader sets. That record loses its opening tag, the parser finds one fewer record start than record end, and the read fails outright:

```
Error in data.frame(...) : arguments imply differing number of rows: 162, 163
```

`ristools` strips the BOM before anything else looks at the text.

**Encoding is detected, not assumed.** Hardcoding `latin1` reinterprets every multi-byte character of a UTF-8 file byte by byte:

| Raw file (UTF-8) | Read as `latin1` | `ristools` |
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

The tag is filled forward across those lines, so all six keywords land under `KW`. This is why the tag pattern requires the `"  - "` separator: with an optional separator, `E7 economies` matches as tag `E7` and the keyword loses its first word, while `EKC` matches entirely and disappears.

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

## OpenAlex

`oa2df()` reads OpenAlex works into a dataframe with no nested columns, and `oa2ristags()` renames those columns to RIS tags, so a search result can go straight to a `.ris` file:

```r
# a saved API response, a list from openalexR::oa_request(), a JSON string,
# or a single work — all accepted
df <- oa2df("openalex_search.json", ris_tags = TRUE)
write_ris(df, "openalex.ris")
```

```
TY  - JOUR
ID  - W2755950973
TI  - bibliometrix: An R-tool for comprehensive science mapping analysis
AU  - Aria, Massimo
AU  - Cuccurullo, Corrado
PY  - 2017
DA  - 2017-11-01
AB  - This paper describes bibliometrix.
KW  - Science Mapping
KW  - Bibliometrics
JO  - Journal of Informetrics
VL  - 11
IS  - 4
SP  - 959
EP  - 975
SN  - 1751-1577
DO  - 10.1016/j.joi.2017.08.007
LA  - en
U1  - Citation
U2  - Scientometrics and Bibliometrics Research
U3  - SDGs: Quality education
N1  - Cited by: 9999
ER  -
```

### Nested fields become delimited strings

Five OpenAlex fields hold arrays of objects rather than single values. Each becomes one column holding the `display_name` of every entry, joined with `" | "` — the same delimiter `write_ris()` splits on, so a five-author paper writes five `AU` lines with nothing further to do.

| OpenAlex field | RIS tag |
|---|---|
| `authorships` | `AU` |
| `concepts` | `U1` |
| `topics` | `U2` |
| `keywords` | `KW` |
| `sustainable_development_goals` | `U3` |

`topics` needs a decision the others do not. Every topic OpenAlex assigns carries a `subfield`, `field` and `domain` alongside it, and the two broad levels are rarely what you want in a reference. `topic_levels` defaults to `c("topic", "subfield")` and drops them. It has to be set here rather than afterwards: once the column is a string, nothing is left to say which level a name came from.

### Differences from `openalexR::oa2df()`

`openalexR::oa2df()` is the reference implementation for this conversion, and returns those five fields as **nested tibbles** (`<tbl_df [5 x 7]>`). `write_ris()` cannot write those: it coerces every column with `as.character()`, so a nested tibble is deparsed into the file as `list(id = c(...), display_name = c(...))`, and a nested `NA` becomes the literal string `"NA"`. The collapse has to happen while the values are still a character vector, which is why this is a separate reader rather than a wrapper.

Column names are the same, so most code transfers. What differs:

| | |
|---|---|
| the five fields above | delimited strings, not nested tibbles |
| `publication_date` | character `"2017-11-01"`, not a `Date` |
| `referenced_works`, `related_works` | delimited strings |
| the result | plain dataframe, not a tibble |
| `ids`, `counts_by_year`, `apc`, `funders`, `awards` | not carried over — no RIS meaning and no atomic form |
| entities | works only; use `openalexR::oa2df()` for authors, sources, … |

`ristools::oa2df()` masks `openalexR::oa2df()` if both packages are attached — call it as `ristools::oa2df()` where both are in play.

### Values that change on the way to RIS

`oa2ristags()` rewrites values where a RIS tag means something narrower than the OpenAlex field:

| Column | Tag | Change |
|---|---|---|
| `type` | `TY` | recoded to a RIS reference type (`article` → `JOUR`, `book-chapter` → `CHAP`, …) |
| `id` | `ID` | `https://openalex.org/` stripped |
| `doi` | `DO` | `https://doi.org/` stripped |
| `cited_by_count` | `N1` | prefixed `"Cited by: "` |
| `sustainable_development_goals` | `U3` | prefixed `"SDGs: "` |
| `authorships` | `AU` | `"Massimo Aria"` → `"Aria, Massimo"` |

A prefix labels *each* value, not the field as a whole, because `write_ris()` writes one line per value: a paper tagged with two SDGs gets two `U3` lines, each beginning `SDGs: `.

`TY` is the one RIS tag with a closed vocabulary, so `article` cannot pass through unchanged. `oa_ris_types()` is the full table. A type not in it becomes `GEN` and is named in a warning, so a work type OpenAlex adds later never blocks a write but never passes unnoticed either.

**Author inversion is a guess, and can be switched off.** A name containing a comma is left alone, a single token is left alone, a trailing `Jr`/`Sr`/`II`/`III`/`IV` stays with the family name, and a *lower-case* particle joins it — so `"Ludo van der Berg"` becomes `"van der Berg, Ludo"` while `"Della Rosa"` becomes `"Rosa, Della"`. The lower-case rule is the one BibTeX uses to find the "von" part of a name.

What it cannot detect is a name OpenAlex already stores family-name first, which is common for Chinese and Korean authors: `"Wang Xiaoming"` is indistinguishable from a given-name-first name and is inverted wrongly. There is no signal in the data separating the two. Pass `invert_authors = FALSE` to leave every name exactly as OpenAlex supplied it.

### Columns with no RIS equivalent

`oa2df()` returns everything it reads, so most of its 40 columns have no RIS tag. They are kept rather than dropped, because `write_ris()` is the single place that decides what reaches a file:

```r
write_ris(df, "openalex.ris")
#> Warning: The following columns are not named with valid RIS tags; they have
#> been excluded from your RIS file: display_name, relevance_score, fwci,
#> is_oa, is_oa_anywhere, oa_status, ...
```

That warning is the design, not a problem — select the columns you want first if you would rather not see it.

## What `write_ris()` will write

A column reaches the file if `tag_map` names it, or the dialect maps it (`author` → `AU`), or it is already one of `ris_valid_tags()`. Anything else is dropped, with one warning naming the columns.

The check is against a fixed list rather than a shape pattern, so a plausible-looking but invalid name such as `TITL` or `SDG1` is dropped too. `ER` is deliberately not on the list: it terminates a record rather than holding a value, so writing it as data splits every record in two. Use `tag_map` to force through a tag that is not on the whitelist:

```r
write_ris(df, "out.ris", tag_map = c(my_field = "U4"))
```

Because the drop happens before any value is read, a list column — which `as.character()` would otherwise deparse into the file — can never reach it.

## Notes and caveats

**`ED` means two things.** `ris_tag_lookup()` lists `ED` twice, as both `editor` and `edition`, because RIS conventions genuinely use it for both. This does not affect reading — columns come from the file, not the table — so it is only something to be aware of when interpreting an `ED` column yourself.

**BibTeX columns are not tags.** A `.bib` file's field names (`author`, `title`, `year`) are not RIS tags, so a BibTeX read is named after those fields. It is the one input format whose column names are not two-character tags.

**Mixing with revtools.** `ristools` does not depend on, load, or modify revtools, and defines no S3 methods on revtools' classes. But if you pass `ristools` output to revtools' own screening functions, note that `format_citation()` and `screen_duplicates()`/`screen_titles()` expect semantically-named columns (`author`, `title`) and split authors on `" and "`. Raw-tag output will not work with them directly.

## API

| Function | Purpose |
|---|---|
| `read_ris()` | read one or more RIS or BibTeX files |
| `write_ris()` | write records as RIS or BibTeX |
| `ris_to_df()` | record list → dataframe |
| `df_to_ris()` | dataframe → record list |
| `ris_sep()` | the multi-value delimiter, `" \| "` |
| `ris_index()` | sequential record names, `ref_01`, `ref_02`, … |
| `ris_tag_lookup()` | what each RIS tag conventionally means |
| `split_ris_file()` | split a large RIS file into chunks |
| `ris_valid_tags()` | the tags `write_ris()` will write |
| `oa2df()` | OpenAlex works (JSON, list, or file) &rarr; dataframe |
| `oa2ristags()` | OpenAlex column names &rarr; RIS tags |
| `oa_ris_tags()` | the OpenAlex column &rarr; RIS tag mapping |
| `oa_ris_types()` | the OpenAlex type &rarr; RIS `TY` mapping |

## License

GPL-3

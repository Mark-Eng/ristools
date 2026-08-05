# ristools 0.3.0

This release narrows the package to what it is for: reading and writing RIS
files without losing anything. Everything that existed to serve semantic field
renaming, or to read formats other than RIS and BibTeX, is gone. That is about a
third of the code.

If you need any of it back, read
`inst/notes/reintroducing-semantic-fields.md` first — it records why each piece
worked the way it did, which parts were already broken, and where the traps are.

## Breaking changes

* **No `label` column.** `read_ris()` and `ris_to_df()` return one column per
  RIS tag in the input and nothing else. Previously a `label` column held a
  generated `Smith_2020_JEco`-style name. Records in the list form
  (`return_df = FALSE`) are still named, but positionally: `ref_1`, `ref_2`, ….
  Building a label from `author`/`year`/`journal` required a full semantic parse
  of the file, which is the reason it is gone. To name records yourself, add a
  `label` column before calling [df_to_ris()].

* **`rename_columns` is removed.** The raw-tag output introduced in 0.2.0 is now
  the only behaviour. Code passing `rename_columns = TRUE` must be rewritten to
  use raw tags (`df$TI` or `df$T1` rather than `df$title`). The argument may
  return in a later version, working differently.

* **Medline (`.nbib`) and Web of Science (`.ciw`) reading is removed.** Both now
  raise an error naming the format rather than being misparsed. Medline reading
  was in fact already unreachable — a `PMID` tag is four characters and could
  never match the RIS tag pattern, so the code had never run on a real file.

* **CSV reading is removed.** `read_ris_csv()` is gone. It was undocumented by
  tests, and its main job was synthesising the `label` column and *guessing* an
  author delimiter from column-wide heuristics — the kind of silent inference
  this package exists to avoid. Use `utils::read.csv()`.

* **`filename` now holds the bare file name.** On a multi-file read the
  `filename` column records `export.ris` rather than the full path it was
  called with. Pass `full_path = TRUE` for the old behaviour. Reading files of
  the same name from different directories warns, because the column can no
  longer identify the source; it is not silently de-duplicated.

* **A file with no `ER` record terminator is rejected.** Fallbacks that treated
  a blank line, or a line of one repeated character, as a record separator are
  gone. Both were untested, and the repeated-character test was itself broken
  (`length(a > 6)` is a line's character count, not a repeat count), so such a
  file was parsed into something arbitrary rather than refused.

* **`ris_tag_lookup()` takes no arguments.** The `medline`, `wos` and
  `ris_write` tables are gone with the formats they served. What remains is the
  RIS table, as user-facing reference data: the answer to "what does `M3` mean?"
  Nothing in the reader consults it, since columns are named from the file
  itself. The two inherited typos (`pubmed_central_identitfier`,
  `wos_cagegories`) went with the deleted tables.

## Bug fixes

* Column order now follows the order fields first appear. Names shorter than
  three characters were previously moved to the end, which was meant to keep raw
  tags behind semantic ones but also reordered any record with a field name of
  three or more characters: `list(TY, ABCD, T1)` came back as `ABCD, TY, T1`.

* A multi-file read no longer leaves the source path in the data frame's row
  names. `rbind()` inherited them from the per-file frames, so every row was
  named after the file it came from; the `label` column had been masking this.

# ristools 0.2.0

## Breaking change

`read_ris()` now defaults to `rename_columns = FALSE`: every field is named
after the raw tag it was read under (`AU`, `TI`, `PY`, `KW`, …), one column per
tag, with no renaming or merging of tags that mean the same thing. A tag
repeated within one record (two `AU` lines, several `KW` lines) becomes a
vector under that one tag, exactly as `author` already did. This makes the
default output mirror the input file as closely as possible: a record can be
read, inspected as a data frame, and written back out with [write_ris()] with
nothing merged or relabelled along the way.

Previously, several tags that carry the same meaning were folded into one
semantic field regardless of source: `author` from `AU` or `A1`; `journal`
from the first of `JO`/`T2`/`T3`/`SO`/`JT`/`JF`/`JA` found (others already kept
their own tag); `pages` from `SP`/`BP` merged with `EP` into one
`"419-41"`-style string. None of this can be reliably reversed after the
merge — a file mixing `KW` and `DE` (both mapped to `keywords`) had no record
of which value came from which tag once they were concatenated. Rather than
add a lossy rename step, `read_ris()` now has two independent parse paths: the
new default builds columns straight from the raw tags, and `rename_columns =
TRUE` calls the same semantic parser as every previous release, unchanged --
existing code that depends on `author`/`title`/`year`/`journal`/`pages`/… keeps
working by adding `rename_columns = TRUE`.

Because the tag used for a given concept differs by source, column names now
vary with the input file: an Ovid export's authors are read into a column
named `A1`, an EconLit export's into `AU`. `pages` is no longer produced at
all under the default; `SP` (or `BP`) and `EP` are separate columns holding
their own unmodified values, and an end-page-only record has no `SP` column.

Applies to RIS, Medline, and Web of Science input alike, each using its own
raw tags. BibTeX (`.bib`) input is unaffected either way, since its field
names (`author=`, `title=`, …) are not RIS tags to begin with.
`write_ris()` needed no changes: it already writes any tag-shaped column
through unchanged, so raw-tag columns round-trip with no special handling.

# ristools 0.1.2

## Bug fixes

* Keywords were silently lost, truncated or misfiled when a RIS file broke a
  multi-value field across several lines without repeating the tag, as every
  EBSCO export does. The tag pattern made the `  - ` separator
  optional, so a continuation line whose first word looked like a tag was
  parsed as one, in two distinct ways:

  - A line with text after the tag-like word was truncated and misfiled.
    `E7 economies` became tag `E7` with text `economies`, so the keyword lost
    its first word and went into a bogus `E7` field; the following keyword
    lines then inherited `E7` from the tag fill-forward. JEL codes broke the
    same way, `F34` splitting into `F3` and `4`.
  - A line that was entirely tag-like left no text at all and was removed by
    the empty-row filter. `EKC` and `GHG` disappeared without warning.

  The read never failed, so a file with 60
  spurious columns still looked like a successful import. RIS tags are always
  two characters -- a capital followed by a capital or a digit -- then two
  spaces and a hyphen, and requiring that separator is enough on its own to
  tell a tag from a keyword. No list of known tags is needed.

  Ovid exports are unaffected, because they repeat the tag on every
  value. Web of Science `.ciw` files use a different tag form entirely (a bare
  single space and no hyphen, as in `AU Smith, J`), so they keep the original
  permissive pattern, selected by file type. The same dispatch is where support
  for other dialects, such as `.nbib` and its `PMID- ` tags, would go.

# ristools 0.1.1

## Bug fixes

Two bugs inherited from revtools 0.4.1, both of which made EBSCO Discovery
exports either unreadable or silently corrupt. Ovid exports are pure ASCII, so
neither was visible on EconLit or Medline files.

* A leading byte order mark broke the read entirely. The BOM's three bytes
  (`EF BB BF`) were reinterpreted as three `latin1` characters before the tag
  pattern was matched, so the first tag of the file stopped matching under the
  `C` locale that `read_ris()` sets. The opening record lost its tag, the
  parser then found one fewer record start than record end, and the read
  failed with `arguments imply differing number of rows: n-1, n`. The BOM is
  now stripped bytewise before the encoding is marked.

* Non-ASCII text was mojibaked, because the encoding was hardcoded to `latin1`
  rather than detected. A `U+2010` hyphen in `socio‐economic` became
  `socioâ€economic`, and curly quotes and accented characters were mangled
  similarly. A following `gsub("<[[:alnum:]]{2}>", "", ...)` then deleted the
  mangled bytes outright, so `Parienté` was silently truncated to `Parient`.
  Text is now marked `UTF-8` when the file is valid UTF-8 and `latin1`
  otherwise, so both encodings read correctly.

* `ris_to_df()` no longer emits one `unable to translate ... to native
  encoding` warning per record with a non-ASCII label (77 warnings on a
  12-file read). `rbind()` was taking row names from the record labels; the
  labels are captured separately and the row names discarded, so the names are
  now dropped beforehand.

Verified on 12 real EBSCO Discovery exports (2,186 records): all read, record
counts match their filenames, no warnings, and accented author names intact.

# ristools 0.1.0

First release. Extracted from the `info_retrieval` repository's
`improved_read_bib.R`, `improved_write_bib.R` and `revtools_shared.R`, a
fidelity-preserving rewrite of revtools 0.4.1's bibliographic read and write
path.

## Features

* `read_ris()` and `write_ris()` read and write RIS, BibTeX, Medline and Web of
  Science files.
* `ris_to_df()` and `df_to_ris()` convert between a record list and a data
  frame, losslessly and reversibly.
* `ris_sep()` defines the multi-value delimiter, `" | "`. Unlike `" and "` it
  cannot occur in bibliographic text, so every field can be split on it and no
  field needs special handling.
* `ris_tag_lookup()` exposes the tag-to-field mapping for each format.
* `split_ris_file()` splits a large export into fixed-size chunks.

## Relative to revtools 0.4.1

* Depends only on base R; `tag_lookup()` is reproduced internally, verified
  identical across all four tag tables.
* Page ranges take their order from the tag, so a range with an abbreviated
  end page is no longer reversed (`419` + `41` gave `41-419`).
* Trailing full stops in titles are kept, so titles ending `U.S.` keep their
  last character.
* Records without an abstract no longer gain an empty one.
* Tags containing a digit (`M3`, `Y2`, `U1`) keep their case on read and their
  digits on write, instead of being dropped.
* Where several tags map to `journal`, extras keep their own tag as a field
  name rather than being pasted into a `journal_secondary` string.
* No S3 methods are defined on revtools' classes, so behaviour does not depend
  on package load order.

## Known behaviour, preserved deliberately

* The RIS tag table maps `ED` to both `editor` and `edition`, so every `ED`
  line is read as two fields.
* The Medline and Web of Science tables keep the upstream typos
  `pubmed_central_identitfier` and `wos_cagegories`.

Both are pinned by tests, so existing files keep parsing identically.
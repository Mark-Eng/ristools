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
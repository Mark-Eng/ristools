# ============================================================================
#  The RIS tag table
#
#  What each RIS tag conventionally means. The reader does not consult this to
#  name its columns -- it uses the tags in the file itself -- so this is
#  reference data, surfaced through ris_tag_lookup(), plus the source of the
#  canonical field order write_ris() emits.
#
#  Tables for Medline and Web of Science tags were dropped in 0.3.0 along with
#  support for reading those formats; see
#  inst/notes/reintroducing-semantic-fields.md.
#
#  Pinned by tests in tests/testthat/test-tag-lookup.R: the 'order' column
#  changes the order write_ris() emits tags in, so it must only change
#  deliberately.
# ============================================================================

# Tag definitions, as name = tag(s). Order matters: the 'order' column is the
# position of each field in this list, which sets the canonical field order of a
# written record.
ris_tag_definitions <- function() {
  list(
    ris = list(
      type = "TY",
      author = c("AU", "A1", "A2", "A3", "A4", "A5"),
      author_full = "AF",
      year = c("PY", "Y1"),
      title = c("TI", "T1"),
      journal = c("JO", "T2", "T3", "SO", "JT", "JF", "JA"),
      volume = "VL",
      issue = "IS",
      pages = c("EP", "BP", "SP"),
      abstract = c("AB", "N2"),
      keywords = c("KW", "DE"),
      doi = c("DO", "DI"),
      call_number = "CN",
      issn = "SN",
      url = "UR",
      accession = "AN",
      institution = "CY",
      publisher = "PB",
      pubplace = "PP",
      address = "AD",
      # FIXME (upstream bug, preserved for now): "ED" appears twice, so a
      # many-to-many merge duplicates every ED line in a file into two rows -
      # once as 'editor' and once as 'edition'. Fixing this needs a decision
      # on which ED means what for a given source, plus its own test.
      editor = "ED",
      edition = "ED",
      language = "LA",
      eppi_id = "U1"
    )
  )
}


#' What each RIS tag conventionally means
#'
#' Reference table of RIS tags and the field each conventionally holds.
#' [read_ris()] names its columns after the tags themselves, so this is the
#' place to look up what a column such as `M3` or `U1` is.
#'
#' @return A data frame with one row per tag and three columns: `ris` (the tag),
#'   `bib` (the field name it conventionally carries), and `order` (an integer
#'   giving the field's canonical position within a record, which is the order
#'   [write_ris()] writes tags in).
#'
#'   Several tags can share a field name — seven map to `journal`, three to
#'   `pages` — which is why [read_ris()] keeps them apart rather than merging
#'   them. `ED` appears twice, mapped to both `editor` and `edition`; the
#'   ambiguity is real and is left for the caller to resolve.
#'
#' @examples
#' head(ris_tag_lookup())
#'
#' # what field does M3 conventionally hold?
#' tags <- ris_tag_lookup()
#' tags[tags$ris == "M3", ]
#'
#' # which tags can carry the journal title?
#' tags$ris[tags$bib == "journal"]
#'
#' @export
ris_tag_lookup <- function() {
  tag_list <- ris_tag_definitions()$ris

  lengths_vec <- lengths(tag_list)
  result <- data.frame(
    ris = unlist(tag_list, use.names = FALSE),
    bib = rep(names(tag_list), lengths_vec),
    stringsAsFactors = FALSE
  )
  rownames(result) <- NULL

  # 'order' is the field's position in the definition list, which drives the
  # canonical field order write_ris() emits
  result$order <- rep(seq_along(tag_list), lengths_vec)

  result
}

# ----------------------------------------------------------------------------
#  The tag whitelist
#
#  Written as a literal rather than derived from ris_write_tags(), so that
#  test-tag-lookup.R can assert the subset relationship and catch a mapping
#  added to a tag that is not a real one.
#
#  "ER" is deliberately absent. It terminates a record rather than carrying a
#  value, so a column named ER must never be written as data: doing so emits a
#  stray "ER  -" mid-record and splits every record in two.
# ----------------------------------------------------------------------------
ris_tag_whitelist <- function() {
  c(
    "TY",
    "A1", "A2", "A3", "A4", "A5", "AB", "AD", "AF", "AN", "AU", "AV",
    "BP", "BT",
    "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "CA", "CN", "CP",
    "CT", "CY",
    "DA", "DB", "DE", "DI", "DO", "DP",
    "ED", "EP", "ET",
    "ID", "IS",
    "J1", "J2", "JA", "JF", "JO", "JT",
    "KW",
    "L1", "L2", "L3", "L4", "LA", "LB", "LK",
    "M1", "M2", "M3",
    "N1", "N2", "NV",
    "OP",
    "PB", "PP", "PT", "PY",
    "RI", "RN", "RP",
    "SE", "SN", "SO", "SP", "ST",
    "T1", "T2", "T3", "TA", "TI", "TT",
    "U1", "U2", "U3", "U4", "U5", "UR",
    "VL", "VO",
    "WP", "WT",
    "Y1", "Y2"
  )
}


#' Which tags [write_ris()] will write
#'
#' The whitelist of RIS tags [write_ris()] accepts. A column whose name is not
#' one of these, and which the tag map does not translate into one, is dropped
#' from the output with a warning.
#'
#' @return A sorted character vector of RIS tags.
#'
#' @details
#' This matters when the data frame did not come from [read_ris()]. Records
#' converted from another source — [oa2risdf()] output, a spreadsheet, an API
#' response — carry column names that are not tags, and writing those verbatim
#' would produce a file no RIS reader can parse. Checking against a fixed list
#' rather than a shape pattern also stops a plausible-looking but invalid name
#' such as `TITL` or `SDG1` from reaching the file.
#'
#' `ER` is **not** on the list. It ends a record rather than holding a value,
#' so a column named `ER` would split every record in two.
#'
#' To write a tag that is not here, map to it explicitly with `write_ris()`'s
#' `tag_map` argument, which is checked before the whitelist.
#'
#' @examples
#' head(ris_valid_tags(), 20)
#'
#' # is this column name writable?
#' "U3" %in% ris_valid_tags()
#' "SDG1" %in% ris_valid_tags()
#'
#' @seealso [ris_tag_lookup()] for what each tag conventionally means,
#'   [write_ris()] for the drop-and-warn behaviour.
#'
#' @export
ris_valid_tags <- function() {
  sort(unique(ris_tag_whitelist()))
}

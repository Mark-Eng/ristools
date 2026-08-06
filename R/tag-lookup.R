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
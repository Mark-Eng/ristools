# ============================================================================
#  Tag lookup tables
#
#  Maps the tags used by RIS, Medline and Web of Science exports to field
#  names. Reproduced as static literals from revtools 0.4.1's tag_lookup(),
#  which built them the same way but was the package's last remaining runtime
#  dependency; inlining them makes ristools base-R only.
#
#  The tables are deliberately verbatim, including two upstream typos and one
#  upstream bug (see below). Changing any of them changes how files parse, so
#  they are pinned by tests in tests/testthat/test-tag-lookup.R.
# ============================================================================

# Tag definitions, as name = tag(s). Order matters: for type = "ris" the
# 'order' column is the position of each field in this list, which is what
# sets the canonical field order of a parsed record.
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
    ),
    # retained for completeness; the writer builds its own tag map in
    # ris_write_tags() rather than inverting this
    ris_write = list(
      type = "TY",
      author = "AU",
      year = "PY",
      title = "TI",
      journal = "JO",
      volume = "VL",
      number = "IS",
      startpage = "SP",
      endpage = "EP",
      abstract = "AB",
      keywords = "KW",
      doi = "DO",
      call = "CN",
      issn = "SN",
      url = "UR",
      accession = "AN",
      institution = "CY",
      publisher = "PB",
      pubplace = "PP",
      address = "AD",
      editor = "ED",
      edition = "ET",
      language = "LA",
      eppi_id = "U1",
      end = "ER"
    ),
    medline = list(
      abstract = "AB",
      copyright_info = "CI",
      affiliation = "AD",
      investigator_affiliation = "IRAD",
      article_id = "AID",
      author = "AU",
      author_id = "AUID",
      author_full = "FAU",
      book_title = "BTI",
      collection_title = "CTI",
      conflict_of_interest = "COI",
      author_corporate = "CN",
      date_created = "CRDT",
      date_completed = "DCOM",
      # 'date_created' appears twice by design: CRDT and DA both carry it
      date_created = "DA",
      date_revised = "LR",
      date_published_elec = "DEP",
      date_published = "DP",
      edition = "EN",
      editor = "ED",
      editor_full = "FED",
      date_added = "EDAT",
      gene_symbol = "GS",
      general_note = "GN",
      grant_number = "GR",
      investigator = "IR",
      investigator_full = "FIR",
      isbn = "ISBN",
      issn = "IS",
      issue = "IP",
      journal_abbreviated = "TA",
      journal = "JT",
      language = "LA",
      location_id = "LID",
      manuscript_id = "MID",
      mesh_date = "MHDA",
      mesh_terms = "MH",
      nlm_id = "JID",
      references_n = "RF",
      abstract_other = "OAB",
      copyright_info_other = "OCI",
      id_other = "OID",
      term_other = "OT",
      term_owner_other = "OTO",
      owner = "OWN",
      pages = "PG",
      personal_name_as_subject = "PS",
      personal_name_as_subject_full = "FPS",
      place_published = "PL",
      publication_history_status = "PHST",
      publication_status = "PST",
      publication_type = "PT",
      publishing_model = "PUBM",
      # upstream typo, kept verbatim ("identitfier")
      pubmed_central_identitfier = "PMC",
      pubmed_central_release = "PMCR",
      pubmed_id = "PMID",
      registry_number = "RN",
      substance_name = "NM",
      secondary_source_id = "SI",
      source = "SO",
      space_flight_mission = "SFM",
      status = "STAT",
      subset = "SB",
      title = "TI",
      title_transliterated = "TT",
      volume = "VI",
      volume_title = "VTI"
    ),
    wos = list(
      file_name = c("FN", "N"),
      version = "VN",
      publication_type = "PT",
      author = "AU",
      author_full = "AF",
      year = "PY",
      date_published = "PD",
      early_access_year = "EY",
      early_access_date = "EA",
      book_author = "BA",
      book_author_full = "BF",
      group_author = "CA",
      group_book_author = "GP",
      author_other_lang = "Z2",
      editor = "BE",
      title = "TI",
      title_other_lang = "Z1",
      title_foreign = "FT",
      book_series_title = "SE",
      book_series_subtitle = "BS",
      source = "SO",
      source_other_lang = "Z3",
      source_abbreviation_29char = "J9",
      source_abbreviation_iso = "JI",
      volume = "VL",
      issue = "IS",
      pages = c("BP", "EP"),
      n_pages = "PG",
      n_chapters = "P2",
      doi = "DI",
      doi_book = "D2",
      author_keywords = "DE",
      keywords_plus = "ID",
      abstract = "AB",
      abstract_other_lang = "Z4",
      author_address = "C1",
      reprint_address = "RP",
      email = "EM",
      orcid_id = "OI",
      researcher_id = "RI",
      special_issue = "SI",
      publisher = "PU",
      publisher_city = "PI",
      publisher_address = "PA",
      conference_title = "CT",
      conference_location = "CL",
      conference_date = "CY",
      conference_host = "HO",
      conference_sponsor = "SP",
      meeting_abstract = "MA",
      funding_agency = "FA",
      funding_text = "FX",
      patent_assignee = "AE",
      patent_number = "PN",
      article_number = "AR",
      supplement = "SU",
      language = "LA",
      document_type = "DT",
      issn = "SN",
      eissn = "EI",
      isbn = "BN",
      accession_number = "UT",
      document_delivery_id = "GA",
      pubmed_id = "PM",
      open_access = "OA",
      # upstream typo, kept verbatim ("cagegories")
      wos_cagegories = "WC",
      research_areas = "SC",
      cited_references = "CR",
      n_cited_references = "NR",
      n_cited_woscc = "TC",
      n_cited_csc = "Z8",
      n_cited_biosis = "ZB",
      n_cited_allwos = "Z9",
      esi_hot_paper = "HP",
      esi_highly_cited = "HC",
      usage_180_days = "U1",
      usage_since_2013 = "U2",
      date_generated = "DA",
      end_record = "ER",
      end_file = "EF"
    )
  )
}


#' Look up the field name for each tag of a bibliographic format
#'
#' Returns the tag-to-field mapping used when parsing a file of the given
#' type. Mostly of internal interest, but exported so a caller can inspect or
#' extend the mapping.
#'
#' @param type One of `"ris"` (the default), `"ris_write"`, `"medline"` or
#'   `"wos"`.
#'
#' @return A data frame with columns `ris` (the tag) and `bib` (the field
#'   name). For `type = "ris"` only, a third integer column `order` gives the
#'   canonical position of each field within a record.
#'
#'   Note that `type = "ris"` contains the tag `ED` twice, mapped to both
#'   `editor` and `edition`; this is inherited from revtools and means every
#'   `ED` line in a file is read as two fields.
#'
#' @examples
#' head(ris_tag_lookup("ris"))
#' nrow(ris_tag_lookup("wos"))
#'
#' @export
ris_tag_lookup <- function(type = c("ris", "ris_write", "medline", "wos")) {
  type <- match.arg(type)
  tag_list <- ris_tag_definitions()[[type]]

  lengths_vec <- lengths(tag_list)
  result <- data.frame(
    ris = unlist(tag_list, use.names = FALSE),
    bib = rep(names(tag_list), lengths_vec),
    stringsAsFactors = FALSE
  )
  rownames(result) <- NULL

  # the 'order' column exists only for "ris": it is the field's position in
  # the definition list, and drives the canonical field order of a record
  if (type == "ris") {
    result$order <- rep(seq_along(tag_list), lengths_vec)
  }

  result
}
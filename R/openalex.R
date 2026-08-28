# ============================================================================
#  OpenAlex -> data frame -> RIS
#
#  openalexR::oa2df() is the reference implementation for this conversion, and
#  produces a tibble whose authorships, concepts, topics, keywords and
#  sustainable_development_goals columns are *nested* tibbles. That shape is
#  right for analysis and wrong for writing RIS: write_ris() coerces each
#  column with as.character(), which deparses a list column into the file as
#  "list(id = c(...), display_name = c(...))", and turns a list column holding
#  a scalar NA into the literal string "NA".
#
#  The collapse cannot be bolted onto that output, because it has to happen
#  while the values are still a plain character vector -- hence a separate
#  reader rather than a wrapper. Every column here is an atomic vector.
#
#  Names follow openalexR's, so a script written against it mostly transfers.
#  Where the two differ it is noted in the roxygen for oa2risdf().
# ============================================================================

# ----------------------------------------------------------------------------
#  Reaching into parsed JSON
#
#  x[["name"]] errors with "subscript out of bounds" when a named list has no
#  such element, which happens constantly: OpenAlex omits fields rather than
#  sending nulls, and a `select=` query omits nearly all of them.
# ----------------------------------------------------------------------------
oa_get <- function(x, name) {
  if (is.null(x) || !is.list(x) || !(name %in% names(x))) {
    return(NULL)
  }
  x[[name]]
}


# a JSON scalar -> a length-1 vector, NA when absent, null or empty
oa_chr <- function(x) {
  if (is.null(x) || length(x) == 0) NA_character_ else as.character(x)[1]
}

oa_int <- function(x) {
  if (is.null(x) || length(x) == 0) {
    NA_integer_
  } else {
    suppressWarnings(as.integer(x)[1])
  }
}

oa_dbl <- function(x) {
  if (is.null(x) || length(x) == 0) {
    NA_real_
  } else {
    suppressWarnings(as.numeric(x)[1])
  }
}

oa_lgl <- function(x) {
  if (is.null(x) || length(x) == 0) NA else as.logical(x)[1]
}


# the same field pulled from every record, as one column
oa_col <- function(recs, name, as = oa_chr, empty = NA_character_) {
  vapply(recs, function(r) as(oa_get(r, name)), empty)
}


# ----------------------------------------------------------------------------
#  Collapsing a nested field to a delimited string
# ----------------------------------------------------------------------------

# drop blanks, optionally de-duplicate, join. NA (not "") when nothing is left,
# so that a record without keywords gets no KW line rather than an empty one.
oa_join <- function(v, delimiter, unique_values = TRUE) {
  v <- trimws(as.character(v))
  v <- v[!is.na(v) & nzchar(v)]
  if (unique_values) {
    v <- unique(v)
  }
  if (!length(v)) {
    return(NA_character_)
  }
  paste(v, collapse = delimiter)
}


# list of objects -> their display_names, joined.
#
# `fields` is a fallback chain: OpenAlex renamed the keywords field from
# "keyword" to "display_name", and both forms are still in circulation.
oa_names_from <- function(
  x,
  delimiter,
  unique_values = TRUE,
  fields = "display_name"
) {
  if (is.null(x) || !length(x)) {
    return(NA_character_)
  }
  v <- vapply(
    x,
    function(el) {
      for (f in fields) {
        d <- oa_get(el, f)
        if (!is.null(d) && length(d)) {
          return(as.character(d)[1])
        }
      }
      NA_character_
    },
    character(1)
  )
  oa_join(v, delimiter, unique_values)
}


# authorships -> author display names, in authorship order.
#
# Not de-duplicated: two authors of one paper can share a display name, and
# silently dropping the second would lose an author.
oa_authors <- function(x, delimiter) {
  if (is.null(x) || !length(x)) {
    return(NA_character_)
  }
  v <- vapply(
    x,
    function(el) oa_chr(oa_get(oa_get(el, "author"), "display_name")),
    character(1)
  )
  oa_join(v, delimiter, unique_values = FALSE)
}


# every level a topic entry can be reported at
oa_topic_levels <- function() {
  c("topic", "subfield", "field", "domain")
}


# topics -> display names at the requested levels, each topic followed by its
# own subfield/field/domain, de-duplicated (one subfield often covers two
# topics). "topic" is the entry itself; the rest are sub-objects on it.
oa_topics <- function(x, delimiter, levels) {
  if (is.null(x) || !length(x)) {
    return(NA_character_)
  }
  v <- unlist(
    lapply(x, function(tp) {
      vapply(
        levels,
        function(lv) {
          node <- if (identical(lv, "topic")) tp else oa_get(tp, lv)
          oa_chr(oa_get(node, "display_name"))
        },
        character(1)
      )
    }),
    use.names = FALSE
  )
  oa_join(v, delimiter, unique_values = TRUE)
}


# abstract_inverted_index -> running text.
#
# The index maps each word to the positions it occupies, so the abstract is
# recovered by sorting words by position. Absent stays absent: a record with no
# index gets NA rather than "", so it gets no AB line at all.
oa_abstract <- function(idx) {
  if (is.null(idx) || !length(idx)) {
    return(NA_character_)
  }
  words <- rep(names(idx), lengths(idx))
  positions <- unlist(idx, use.names = FALSE)
  if (!length(positions)) {
    return(NA_character_)
  }
  paste(words[order(positions)], collapse = " ")
}


# ----------------------------------------------------------------------------
#  Working out what was handed to us
# ----------------------------------------------------------------------------

# a work object, as opposed to a list of them or an API envelope
oa_is_work <- function(x) {
  is.list(x) &&
    !is.null(names(x)) &&
    any(c("id", "display_name", "title") %in% names(x)) &&
    !("results" %in% names(x))
}


# anything oa2risdf() accepts -> a plain list of work objects
oa_records <- function(data) {
  if (is.character(data)) {
    if (length(data) != 1 || is.na(data)) {
      stop(
        "'data' must be a single file path or JSON string, not a vector",
        call. = FALSE
      )
    }
    if (file.exists(data)) {
      data <- jsonlite::fromJSON(data, simplifyVector = FALSE)
    } else if (grepl("^[[:space:]]*[[{]", data)) {
      data <- jsonlite::fromJSON(data, simplifyVector = FALSE)
    } else {
      stop(
        "'data' is a string but is neither an existing file nor JSON: ",
        substr(data, 1, 60),
        call. = FALSE
      )
    }
  }
  if (!is.list(data)) {
    stop(
      "'data' must be a list of OpenAlex records, a path to a .json file, ",
      "or a JSON string",
      call. = FALSE
    )
  }
  if (!length(data)) {
    return(list())
  }

  # a whole API response: {"meta": ..., "results": [...], "group_by": []}
  if (!is.null(oa_get(data, "results"))) {
    return(oa_get(data, "results"))
  }
  # several of them, as a paged fetch saved page by page
  pages <- vapply(
    data,
    function(el) is.list(el) && !is.null(oa_get(el, "results")),
    logical(1)
  )
  if (all(pages)) {
    return(unlist(lapply(data, oa_get, "results"), recursive = FALSE))
  }
  # a single work, fetched by id
  if (oa_is_work(data)) {
    return(list(data))
  }
  data
}


# refuse an entity we cannot map, rather than returning a frame of NAs
oa_check_works <- function(recs) {
  if (!length(recs)) {
    return(invisible(NULL))
  }
  first <- recs[[1]]
  if (!is.list(first)) {
    stop("'data' does not contain OpenAlex records", call. = FALSE)
  }
  work_fields <- c(
    "authorships",
    "publication_year",
    "publication_date",
    "biblio",
    "primary_location",
    "referenced_works",
    "abstract_inverted_index"
  )
  if (!any(work_fields %in% names(first))) {
    stop(
      "oa2risdf() converts OpenAlex *works*. These records look like a ",
      "different entity (authors, institutions, sources, ...); use ",
      "openalexR::oa2df() for those.",
      call. = FALSE
    )
  }
  invisible(NULL)
}


# the columns oa2risdf() produces, in order
oa_columns <- function(abstract = TRUE) {
  cols <- c(
    "id",
    "title",
    "display_name",
    "authorships",
    "abstract",
    "doi",
    "publication_date",
    "publication_year",
    "relevance_score",
    "fwci",
    "cited_by_count",
    "type",
    "is_oa",
    "is_oa_anywhere",
    "oa_status",
    "oa_url",
    "any_repository_has_fulltext",
    "source_display_name",
    "source_id",
    "issn_l",
    "host_organization",
    "host_organization_name",
    "landing_page_url",
    "pdf_url",
    "license",
    "version",
    "referenced_works",
    "referenced_works_count",
    "related_works",
    "concepts",
    "topics",
    "keywords",
    "is_paratext",
    "is_retracted",
    "language",
    "sustainable_development_goals",
    "first_page",
    "last_page",
    "volume",
    "issue"
  )
  if (!abstract) {
    cols <- setdiff(cols, "abstract")
  }
  cols
}


# ----------------------------------------------------------------------------
#  OpenAlex -> asysd column names
#
#  asysd (https://github.com/camaradesuk/ASySD) expects a narrower, differently
#  named set of columns. This is a pure rename, kept separate from the RIS tag
#  mapping below: apply_ris_tags() still has to recognise these names, so both
#  live off the same table of RIS aliases.
# ----------------------------------------------------------------------------

# oa2risdf() column -> asysd column, for the columns asysd renames
oa_asysd_map <- function() {
  c(
    id = "openalex_id",
    authorships = "author",
    publication_year = "year",
    source_display_name = "journal",
    issue = "number",
    issn_l = "isbn"
  )
}


oa_asysd_rename <- function(df) {
  m <- oa_asysd_map()
  present <- intersect(names(m), colnames(df))
  colnames(df)[match(present, colnames(df))] <- unname(m[present])
  df
}


# dispatch table for oa2risdf()'s col_names argument, shared by the empty-
# result early return and the normal path
oa_apply_col_names <- function(df, col_names, invert_authors, delimiter) {
  switch(
    col_names,
    keep = df,
    ris = apply_ris_tags(df, invert_authors = invert_authors, delimiter = delimiter),
    asysd = oa_asysd_rename(df)
  )
}


#' Read OpenAlex works into a data frame
#'
#' Converts OpenAlex work records into a data frame with one row per work and
#' no nested columns, ready for [write_ris()].
#'
#' @param data OpenAlex works, as any of: a list of work records (the output of
#'   `openalexR::oa_request()`, or of `jsonlite::fromJSON(simplifyVector =
#'   FALSE)`); a whole API response, with its `meta`/`results` envelope; a list
#'   of such responses, from a paged fetch; a single work record; a path to a
#'   `.json` file holding any of those; or a JSON string.
#' @param col_names How to name the result's columns. One of:
#'   * `"keep"` (the default): the [oa2risdf()] names described below.
#'   * `"ris"`: passed through [apply_ris_tags()], so columns come back named
#'     with RIS tags.
#'   * `"asysd"`: renamed to the column names
#'     [asysd](https://github.com/camaradesuk/ASySD) expects: `id` becomes
#'     `openalex_id`, `authorships` becomes `author`, `publication_year`
#'     becomes `year`, `source_display_name` becomes `journal`, `issue`
#'     becomes `number`, and `issn_l` becomes `isbn`. Every other column keeps
#'     its `oa2risdf()` name.
#' @param abstract If `TRUE` (the default), abstracts are rebuilt from
#'   `abstract_inverted_index`. If `FALSE`, no `abstract` column is created.
#' @param topic_levels Which levels of the `topics` field to keep: any of
#'   `"topic"`, `"subfield"`, `"field"`, `"domain"`, or `NULL` for all four.
#'   Defaults to `c("topic", "subfield")`, dropping the broad field and domain
#'   rows. See details.
#' @param invert_authors Passed to [apply_ris_tags()]; only has an effect when
#'   `col_names = "ris"`.
#' @param delimiter The string used to join multiple values in one field.
#'   Defaults to [ris_sep()].
#'
#' @return A data frame with one row per work. Every column is an atomic
#'   vector - there are no list columns and no nested tables.
#'
#' @details
#' Five OpenAlex fields hold arrays of objects rather than single values:
#' `authorships`, `concepts`, `topics`, `keywords` and
#' `sustainable_development_goals`. Each becomes one column holding the
#' `display_name` of every entry, joined with `delimiter`. Since that is the
#' same delimiter [write_ris()] splits on, a five-author paper writes five `AU`
#' lines without any further work.
#'
#' Authors keep authorship order and are not de-duplicated. The other four are
#' de-duplicated and keep the order OpenAlex returns, which is by descending
#' score.
#'
#' `topic_levels` has to be applied here rather than in [apply_ris_tags()]. Each
#' topic OpenAlex assigns carries a `subfield`, `field` and `domain` alongside
#' it, and once the column is collapsed to a string there is nothing left to
#' say which level a name came from. The default keeps the two specific levels
#' and drops the two broad ones.
#'
#' @section Differences from openalexR::oa2df():
#' Column names are the same, so most code transfers. The differences:
#'
#' * The five fields above are delimited strings, not nested tibbles.
#' * `publication_date` is a character `"2017-11-01"`, not a `Date`.
#' * `referenced_works` and `related_works` are delimited strings.
#' * The result is a plain data frame, not a tibble.
#' * Fields with no RIS meaning and no atomic form are not carried over at
#'   all: `ids`, `counts_by_year`, `apc`, `funders` and `awards`.
#' * Only works are handled. Use `openalexR::oa2df()` for other entities.
#'
#' @examples
#' works <- list(list(
#'   id = "https://openalex.org/W2755950973",
#'   title = "bibliometrix: An R-tool for comprehensive science mapping",
#'   type = "article",
#'   publication_year = 2017L,
#'   authorships = list(
#'     list(author = list(display_name = "Massimo Aria")),
#'     list(author = list(display_name = "Corrado Cuccurullo"))
#'   ),
#'   keywords = list(list(display_name = "Bibliometrics"))
#' ))
#'
#' df <- oa2risdf(works)
#' df$authorships
#' df$keywords
#'
#' # straight to RIS tags
#' oa2risdf(works, col_names = "ris")[, c("TY", "ID", "AU")]
#'
#' @seealso [apply_ris_tags()] to rename the columns to RIS tags, [write_ris()]
#'   to write the result out, [ris_valid_tags()] for what survives that write.
#'
#' @importFrom jsonlite fromJSON
#' @export
oa2risdf <- function(
  data,
  col_names = c("keep", "ris", "asysd"),
  abstract = TRUE,
  topic_levels = c("topic", "subfield"),
  invert_authors = TRUE,
  delimiter = ris_sep()
) {
  col_names <- match.arg(col_names)
  if (is.null(topic_levels)) {
    topic_levels <- oa_topic_levels()
  }
  topic_levels <- match.arg(topic_levels, oa_topic_levels(), several.ok = TRUE)

  recs <- oa_records(data)
  oa_check_works(recs)
  cols <- oa_columns(abstract)

  if (!length(recs)) {
    empty <- data.frame(
      stats::setNames(rep(list(character(0)), length(cols)), cols),
      stringsAsFactors = FALSE
    )
    return(oa_apply_col_names(empty, col_names, invert_authors, delimiter))
  }

  # the sub-objects several columns are read out of
  loc <- lapply(recs, oa_get, "primary_location")
  src <- lapply(loc, oa_get, "source")
  acc <- lapply(recs, oa_get, "open_access")
  bib <- lapply(recs, oa_get, "biblio")

  from <- function(lst, name, as = oa_chr, empty = NA_character_) {
    vapply(lst, function(el) as(oa_get(el, name)), empty)
  }
  per_record <- function(f, empty = NA_character_) {
    vapply(recs, f, empty)
  }

  out <- list(
    id = oa_col(recs, "id"),
    title = oa_col(recs, "title"),
    display_name = oa_col(recs, "display_name"),
    authorships = per_record(function(r) {
      oa_authors(oa_get(r, "authorships"), delimiter)
    }),
    abstract = per_record(function(r) {
      oa_abstract(oa_get(r, "abstract_inverted_index"))
    }),
    doi = oa_col(recs, "doi"),
    publication_date = oa_col(recs, "publication_date"),
    publication_year = oa_col(recs, "publication_year", oa_int, NA_integer_),
    relevance_score = oa_col(recs, "relevance_score", oa_dbl, NA_real_),
    fwci = oa_col(recs, "fwci", oa_dbl, NA_real_),
    cited_by_count = oa_col(recs, "cited_by_count", oa_int, NA_integer_),
    type = oa_col(recs, "type"),
    is_oa = from(loc, "is_oa", oa_lgl, NA),
    is_oa_anywhere = from(acc, "is_oa", oa_lgl, NA),
    oa_status = from(acc, "oa_status"),
    oa_url = from(acc, "oa_url"),
    any_repository_has_fulltext = from(
      acc,
      "any_repository_has_fulltext",
      oa_lgl,
      NA
    ),
    source_display_name = from(src, "display_name"),
    source_id = from(src, "id"),
    issn_l = from(src, "issn_l"),
    host_organization = from(src, "host_organization"),
    host_organization_name = from(src, "host_organization_name"),
    landing_page_url = from(loc, "landing_page_url"),
    pdf_url = from(loc, "pdf_url"),
    license = from(loc, "license"),
    version = from(loc, "version"),
    referenced_works = per_record(function(r) {
      oa_join(unlist(oa_get(r, "referenced_works")), delimiter)
    }),
    referenced_works_count = oa_col(
      recs,
      "referenced_works_count",
      oa_int,
      NA_integer_
    ),
    related_works = per_record(function(r) {
      oa_join(unlist(oa_get(r, "related_works")), delimiter)
    }),
    concepts = per_record(function(r) {
      oa_names_from(oa_get(r, "concepts"), delimiter)
    }),
    topics = per_record(function(r) {
      oa_topics(oa_get(r, "topics"), delimiter, topic_levels)
    }),
    keywords = per_record(function(r) {
      oa_names_from(
        oa_get(r, "keywords"),
        delimiter,
        fields = c("display_name", "keyword")
      )
    }),
    is_paratext = oa_col(recs, "is_paratext", oa_lgl, NA),
    is_retracted = oa_col(recs, "is_retracted", oa_lgl, NA),
    language = oa_col(recs, "language"),
    sustainable_development_goals = per_record(function(r) {
      oa_names_from(oa_get(r, "sustainable_development_goals"), delimiter)
    }),
    first_page = from(bib, "first_page"),
    last_page = from(bib, "last_page"),
    volume = from(bib, "volume"),
    issue = from(bib, "issue")
  )

  df <- data.frame(out[cols], stringsAsFactors = FALSE)
  rownames(df) <- NULL

  oa_apply_col_names(df, col_names, invert_authors, delimiter)
}


# ----------------------------------------------------------------------------
#  OpenAlex -> RIS
# ----------------------------------------------------------------------------

#' How OpenAlex columns map to RIS tags
#'
#' The column-name mapping [apply_ris_tags()] applies, as a table.
#'
#' @return A data frame with one row per mapped column and two columns: `oa`
#'   (the [oa2risdf()] column name) and `ris` (the RIS tag it becomes).
#'
#' @details
#' Rows are in the order [apply_ris_tags()] puts the columns in. Any
#' [oa2risdf()] column not listed here keeps its OpenAlex name, and is
#' therefore dropped by
#' [write_ris()] with a warning.
#'
#' Some of these mappings change the value as well as the name, because the RIS
#' tag means something narrower than the OpenAlex field: `cited_by_count` is
#' prefixed `"Cited by: "` for the notes tag `N1`, and
#' `sustainable_development_goals` is prefixed `"SDGs: "` for the user tag
#' `U3`, so neither is mistaken for a plain note. `type` is recoded to a RIS
#' reference type by the table in [oa_ris_types()].
#'
#' @examples
#' oa_ris_tags()
#'
#' # which tag do keywords land in?
#' m <- oa_ris_tags()
#' m$ris[m$oa == "keywords"]
#'
#' @seealso [oa_ris_types()] for the reference-type recode,
#'   [ris_tag_lookup()] for what each RIS tag conventionally means.
#'
#' @export
oa_ris_tags <- function() {
  data.frame(
    oa = c(
      "type",
      "id",
      "title",
      "authorships",
      "abstract",
      "doi",
      "publication_date",
      "publication_year",
      "cited_by_count",
      "source_display_name",
      "issn_l",
      "keywords",
      "topics",
      "sustainable_development_goals",
      "language",
      "first_page",
      "last_page",
      "volume",
      "issue"
    ),
    ris = c(
      "TY",
      "ID",
      "TI",
      "AU",
      "AB",
      "DO",
      "DA",
      "PY",
      "N1",
      "JO",
      "SN",
      "KW",
      "U1",
      "U3",
      "LA",
      "SP",
      "EP",
      "VL",
      "IS"
    ),
    stringsAsFactors = FALSE
  )
}


#' How OpenAlex work types map to RIS reference types
#'
#' The `TY` recode [apply_ris_tags()] applies, as a table.
#'
#' @return A data frame with one row per OpenAlex work type and two columns:
#'   `openalex` (the `type` value, lower case) and `ris` (the RIS reference
#'   type it becomes).
#'
#' @details
#' `TY` is the one RIS tag with a closed vocabulary, so an OpenAlex `type` of
#' `"article"` cannot be written through unchanged - a reader expects `JOUR`.
#' RIS has no separate type for a review, editorial, letter, erratum,
#' retraction or peer review, all of which appear in a journal, so all six map
#' to `JOUR`.
#'
#' A `type` that is not in this table, or missing, becomes `GEN` (the generic
#' type) and is named in a warning, so that a work type OpenAlex adds later
#' never blocks a write but never passes unnoticed either.
#'
#' @examples
#' oa_ris_types()
#'
#' # what does a preprint become?
#' m <- oa_ris_types()
#' m$ris[m$openalex == "preprint"]
#'
#' @seealso [oa_ris_tags()] for the column-name mapping.
#'
#' @export
oa_ris_types <- function() {
  pairs <- c(
    article = "JOUR",
    `journal-article` = "JOUR",
    review = "JOUR",
    editorial = "JOUR",
    letter = "JOUR",
    erratum = "JOUR",
    retraction = "JOUR",
    `peer-review` = "JOUR",
    book = "BOOK",
    monograph = "BOOK",
    `reference-book` = "BOOK",
    `edited-book` = "EDBOOK",
    `book-chapter` = "CHAP",
    `book-part` = "CHAP",
    `book-series` = "SER",
    `reference-entry` = "ENCYC",
    `proceedings-article` = "CPAPER",
    proceedings = "CONF",
    dissertation = "THES",
    report = "RPRT",
    `report-component` = "RPRT",
    dataset = "DATA",
    preprint = "UNPB",
    `posted-content` = "UNPB",
    standard = "STAND",
    grant = "GRANT",
    libguides = "ELEC",
    `supplementary-materials` = "GEN",
    component = "GEN",
    paratext = "GEN",
    other = "GEN"
  )
  data.frame(
    openalex = names(pairs),
    ris = unname(pairs),
    stringsAsFactors = FALSE
  )
}


# OpenAlex type values -> RIS reference types, GEN for anything unrecognised
oa_type_to_ris <- function(value) {
  v <- tolower(trimws(as.character(value)))
  v[!is.na(v) & !nzchar(v)] <- NA_character_
  m <- oa_ris_types()
  out <- m$ris[match(v, m$openalex)]

  unknown <- unique(v[!is.na(v) & is.na(out)])
  missing <- any(is.na(v))
  if (length(unknown) > 0 || missing) {
    warning(
      "no RIS reference type for work type(s): ",
      paste(c(unknown, if (missing) "<missing>"), collapse = ", "),
      "; written as GEN",
      call. = FALSE
    )
  }
  # never leave a record without a TY: readers, this package's included, find
  # record boundaries by the opening tag
  out[is.na(out)] <- "GEN"
  out
}


# ----------------------------------------------------------------------------
#  Author names
#
#  OpenAlex reports an author's display_name given-name first ("Massimo Aria").
#  RIS consumers read AU as "Family, Given". The inversion cannot be done
#  reliably -- see the roxygen for apply_ris_tags() -- so every rule here is
#  deliberately conservative, and the whole step can be switched off.
# ----------------------------------------------------------------------------

# lower-cased nobiliary particles that belong to the family name. Matched only
# when they are lower case in the original, which is the rule BibTeX uses to
# find the "von" part of a name, and which keeps "Della" as a given name while
# treating "della" as part of the surname.
oa_name_particles <- function() {
  c(
    "van",
    "von",
    "der",
    "den",
    "de",
    "del",
    "della",
    "di",
    "da",
    "dos",
    "das",
    "du",
    "la",
    "le",
    "ter",
    "ten",
    "af",
    "av",
    "bin",
    "ibn",
    "al",
    "el",
    "zu",
    "zur",
    "'t"
  )
}


oa_name_suffixes <- function() {
  c("jr", "jr.", "sr", "sr.", "ii", "iii", "iv")
}


# "Massimo Aria" -> "Aria, Massimo"
oa_invert_name <- function(name) {
  if (is.na(name)) {
    return(NA_character_)
  }
  # a comma means it is already inverted, or is a form we should not touch
  if (grepl(",", name, fixed = TRUE)) {
    return(name)
  }
  parts <- strsplit(trimws(name), "[[:space:]]+")[[1]]
  parts <- parts[nzchar(parts)]
  # a single token is a mononym or an organisation; there is nothing to invert
  if (length(parts) < 2) {
    return(name)
  }

  suffix <- character(0)
  last <- parts[length(parts)]
  if (tolower(last) %in% oa_name_suffixes() && length(parts) > 2) {
    suffix <- last
    parts <- parts[-length(parts)]
  }

  # walk back over particles, stopping while a given name is still left
  i <- length(parts)
  particles <- oa_name_particles()
  while (
    i > 2 &&
      tolower(parts[i - 1]) %in% particles &&
      identical(parts[i - 1], tolower(parts[i - 1]))
  ) {
    i <- i - 1
  }

  family <- paste(c(parts[i:length(parts)], suffix), collapse = " ")
  given <- paste(parts[seq_len(i - 1)], collapse = " ")
  paste0(family, ", ", given)
}


# the same, over a column of delimiter-joined names
oa_invert_author_field <- function(v, delimiter) {
  vapply(
    as.character(v),
    function(s) {
      if (is.na(s)) {
        return(NA_character_)
      }
      one <- trimws(strsplit(s, delimiter, fixed = TRUE)[[1]])
      paste(
        vapply(one, oa_invert_name, character(1), USE.NAMES = FALSE),
        collapse = delimiter
      )
    },
    character(1),
    USE.NAMES = FALSE
  )
}


# ----------------------------------------------------------------------------
#  Value tidying
# ----------------------------------------------------------------------------

# Label each value in a field with a prefix.
#
# Per value, not per field: write_ris() emits one line per value, so a field
# labelled once would put "SDGs: Quality education" on the first line and leave
# the second line unlabelled. Every line that reaches the file says what it is.
#
# The prefix is added only where it is absent, so apply_ris_tags() run twice cannot
# produce "Cited by: Cited by: 42".
oa_add_prefix <- function(v, prefix, delimiter = ris_sep()) {
  vapply(
    as.character(v),
    function(s) {
      if (is.na(s) || !nzchar(trimws(s))) {
        return(NA_character_)
      }
      parts <- trimws(strsplit(s, delimiter, fixed = TRUE)[[1]])
      parts <- parts[nzchar(parts)]
      if (!length(parts)) {
        return(NA_character_)
      }
      labelled <- ifelse(
        startsWith(parts, prefix),
        parts,
        paste0(prefix, parts)
      )
      paste(labelled, collapse = delimiter)
    },
    character(1),
    USE.NAMES = FALSE
  )
}


oa_strip_prefix <- function(v, prefix) {
  v <- as.character(v)
  out <- sub(prefix, "", v, fixed = TRUE)
  out[is.na(v)] <- NA_character_
  out
}


# oa_ris_tags(), extended with the asysd column names that reach the same RIS
# tag by an alternate name (e.g. "author" alongside "authorships" -> "AU")
oa_ris_tag_aliases <- function() {
  m <- oa_ris_tags()
  asysd <- oa_asysd_map()
  asysd <- asysd[names(asysd) %in% m$oa]
  extra <- data.frame(
    oa = unname(asysd),
    ris = m$ris[match(names(asysd), m$oa)],
    stringsAsFactors = FALSE
  )
  rbind(m, extra)
}


#' Rename OpenAlex columns to RIS tags
#'
#' Converts the column names - and, where a RIS tag means something narrower
#' than the OpenAlex field, the values - of an [oa2risdf()] data frame into RIS
#' form, ready for [write_ris()].
#'
#' @param x A data frame with [oa2risdf()]-style column names, in either the
#'   default (`col_names = "keep"`) or `col_names = "asysd"` form - see
#'   details.
#' @param invert_authors If `TRUE` (the default), author names are rewritten
#'   from `"Massimo Aria"` to `"Aria, Massimo"`, the form RIS consumers expect.
#'   See details for what this cannot get right.
#' @param delimiter The delimiter separating multiple values in a field.
#'   Defaults to [ris_sep()]. Used to split the columns that are rewritten
#'   value by value: authors, and the two that take a prefix.
#'
#' @return `x` with the mapped columns renamed to RIS tags and moved to the
#'   front, in the order of [oa_ris_tags()]. Unmapped columns keep their names
#'   and follow.
#'
#' @details
#' The name mapping is [oa_ris_tags()], extended with the alternate names
#' [oa2risdf()]'s `col_names = "asysd"` produces: `openalex_id` is recognised
#' alongside `id`, and so on for `authorships`/`author`,
#' `publication_year`/`year`, `source_display_name`/`journal`,
#' `issue`/`number` and `issn_l`/`isbn`. Unmapped columns are deliberately kept
#' rather than dropped, so that [write_ris()] is the single place that decides
#' what reaches a file - it drops them there, naming them in a warning.
#'
#' If `x` has two columns that map to the same RIS tag - `authorships` and its
#' asysd alias `author`, say, both present at once - that is refused with an
#' error naming both columns and the tag, rather than silently keeping one of
#' them.
#'
#' Five mappings change the value too:
#'
#' | Column | Tag | Change |
#' |---|---|---|
#' | `type` | `TY` | recoded to a RIS reference type; see [oa_ris_types()] |
#' | `id` / `openalex_id` | `ID` | `https://openalex.org/` stripped, leaving `W2755950973` |
#' | `doi` | `DO` | `https://doi.org/` stripped, leaving the bare DOI |
#' | `cited_by_count` | `N1` | prefixed `"Cited by: "` |
#' | `sustainable_development_goals` | `U3` | prefixed `"SDGs: "` |
#'
#' A prefix labels *each* value in the field, not the field as a whole, since
#' [write_ris()] writes one line per value: a paper tagged with two SDGs gets
#' two `U3` lines, each beginning `"SDGs: "`. Prefixes are added only where
#' absent, and the function returns `x` unchanged with a message if its columns
#' are already RIS tags, so calling it twice cannot produce
#' `"Cited by: Cited by: 42"`.
#'
#' `publication_date` is written to `DA` as OpenAlex supplies it,
#' `"2017-11-01"`, rather than the `"2017/11/01"` some RIS writers use.
#'
#' @section What author inversion cannot do:
#' Turning `"Massimo Aria"` into `"Aria, Massimo"` is a guess about which
#' tokens are the family name, and some of those guesses are wrong. The rules,
#' in order:
#'
#' * a name containing a comma is left alone - it is already inverted
#' * a single token is left alone - a mononym or an organisation
#' * a trailing `Jr`, `Sr`, `II`, `III` or `IV` stays with the family name
#' * a **lower-case** particle (`van`, `de`, `della`, `bin`, ...) before the
#'   last token joins the family name, so `"Ludo van der Berg"` becomes
#'   `"van der Berg, Ludo"`. The lower-case requirement is the rule BibTeX uses
#'   to find the "von" part of a name; it means `"Della"` stays a given name.
#'
#' The case it cannot detect is a name OpenAlex already stores family-name
#' first, which is common for Chinese and Korean authors: `"Wang Xiaoming"` is
#' indistinguishable from a given-name-first name and is inverted wrongly.
#' There is no signal in the data to separate the two, which is why
#' `invert_authors = FALSE` exists - it leaves every name exactly as OpenAlex
#' supplied it.
#'
#' @examples
#' df <- data.frame(
#'   id = "https://openalex.org/W2755950973",
#'   type = "article",
#'   title = "A study",
#'   authorships = "Massimo Aria | Ludo van der Berg",
#'   cited_by_count = 42L,
#'   fwci = 3.1,
#'   stringsAsFactors = FALSE
#' )
#'
#' out <- apply_ris_tags(df)
#' colnames(out)
#' out$AU
#' out$TY
#' out$N1
#'
#' # fwci has no RIS tag, so it survives here and is dropped by write_ris()
#' "fwci" %in% colnames(out)
#'
#' @seealso [oa2risdf()], which calls this when `col_names = "ris"`;
#'   [oa_ris_tags()] and [oa_ris_types()] for the two mapping tables.
#'
#' @export
apply_ris_tags <- function(x, invert_authors = TRUE, delimiter = ris_sep()) {
  if (!inherits(x, "data.frame")) {
    stop("apply_ris_tags can only be called on objects of class 'data.frame'")
  }
  m <- oa_ris_tag_aliases()
  present <- intersect(m$oa, colnames(x))

  if (!length(present)) {
    if (any(colnames(x) %in% m$ris)) {
      message(
        "apply_ris_tags(): these columns are already named with RIS tags; ",
        "returning unchanged."
      )
    } else {
      warning(
        "apply_ris_tags(): no OpenAlex columns recognised; returning unchanged.",
        call. = FALSE
      )
    }
    return(x)
  }

  # a column and its asysd alias (e.g. "authorships" and "author") can both be
  # present and target the same tag; that has to be refused, not resolved
  present_ris <- m$ris[match(present, m$oa)]
  conflicts <- unique(present_ris[duplicated(present_ris)])
  if (length(conflicts)) {
    stop(
      paste(
        vapply(
          conflicts,
          function(tag) {
            cols <- present[present_ris == tag]
            paste0(
              "\"", paste(cols, collapse = "\" and \""),
              "\" both map to RIS tag \"", tag, "\""
            )
          },
          character(1)
        ),
        collapse = "; "
      ),
      ". Choose which of the columns you would like to be included in the ",
      "RIS file, and rename the other to something else.",
      call. = FALSE
    )
  }

  # the present column - canonical or asysd alias - that maps to the same tag
  # as `canonical`
  col_for <- function(canonical) {
    tag <- m$ris[m$oa == canonical][1]
    present[present_ris == tag]
  }

  # values first, while the columns still have names that say what they hold
  type_col <- col_for("type")
  if (length(type_col)) {
    x[[type_col]] <- oa_type_to_ris(x[[type_col]])
  }
  id_col <- col_for("id")
  if (length(id_col)) {
    x[[id_col]] <- oa_strip_prefix(x[[id_col]], "https://openalex.org/")
  }
  doi_col <- col_for("doi")
  if (length(doi_col)) {
    x[[doi_col]] <- oa_strip_prefix(x[[doi_col]], "https://doi.org/")
  }
  cited_col <- col_for("cited_by_count")
  if (length(cited_col)) {
    x[[cited_col]] <- oa_add_prefix(x[[cited_col]], "Cited by: ", delimiter)
  }
  sdg_col <- col_for("sustainable_development_goals")
  if (length(sdg_col)) {
    x[[sdg_col]] <- oa_add_prefix(x[[sdg_col]], "SDGs: ", delimiter)
  }
  author_col <- col_for("authorships")
  if (invert_authors && length(author_col)) {
    x[[author_col]] <- oa_invert_author_field(x[[author_col]], delimiter)
  }

  # mapped columns first, in oa_ris_tags() order; the rest keep their place
  rest <- setdiff(colnames(x), present)
  ris_order <- oa_ris_tags()$ris
  ordered_tags <- ris_order[ris_order %in% present_ris]
  ordered <- unlist(lapply(
    ordered_tags,
    function(tag) present[present_ris == tag]
  ))
  x <- x[, c(ordered, rest), drop = FALSE]
  colnames(x) <- c(ordered_tags, rest)
  x
}

# ============================================================================
#  Writing bibliographic files
#
#  Round-trip-safe replacement for revtools 0.4.1's write_bibliography().
#  Notably it does not use an inverted tag lookup, which is where most of that
#  version's information loss came from.
# ============================================================================

# ----------------------------------------------------------------------------
#  Tag maps used when writing RIS
#
#  $map   field name -> RIS tag
#  $order canonical order of RIS tags within a record (TY first, ER added last)
#
#  "ovid"    the tags an Ovid / EndNote style export actually uses, i.e. the
#            tags ris_tag_lookup("ris") maps *from*: T1 / A1 / Y1 / N2 / JF.
#            Round-trips an Ovid export unchanged.
#  "generic" the tags revtools <= 0.4.1 wrote: TI / AU / PY / AB / JO.
# ----------------------------------------------------------------------------
ris_write_tags <- function(dialect = c("ovid", "generic")) {
  dialect <- match.arg(dialect)
  ovid <- identical(dialect, "ovid")

  map <- c(
    type = "TY",
    title = if (ovid) "T1" else "TI",
    title_secondary = "T2",
    # read_ris() no longer creates journal_secondary (extra journal tags keep
    # their own name), but revtools' reader did, so it is kept here for
    # records produced by that version
    journal_secondary = "T3",
    author = if (ovid) "A1" else "AU",
    author_full = "AF",
    year = if (ovid) "Y1" else "PY",
    year_additional = "Y2", # created when a file has two year tags
    abstract = if (ovid) "N2" else "AB",
    keywords = "KW",
    journal = if (ovid) "JF" else "JO",
    volume = "VL",
    issue = "IS",
    number = "IS",
    startpage = "SP",
    endpage = "EP",
    publisher = "PB",
    issn = "SN",
    isbn = "SN",
    doi = "DO",
    call_number = "CN",
    call = "CN",
    url = "UR",
    accession = "AN",
    institution = "CY",
    pubplace = "PP",
    address = "AD",
    editor = "ED",
    edition = "ET",
    language = "LA",
    eppi_id = "U1"
  )

  # canonical within-record order; anything not listed keeps its incoming
  # order and is written after these, immediately before ER
  tag_order <- c(
    "TY", "DB", "ID", "T1", "TI", "T2", "T3", "A1", "AU", "A2", "A3", "AF",
    "Y1", "PY", "Y2", "N2", "AB", "M3", "KW", "DE", "JF", "JO", "JA", "JT",
    "SO", "VL", "IS", "SP", "BP", "EP", "PB", "SN", "DO", "DI", "PT", "UR",
    "AN", "CY", "PP", "AD", "ED", "ET", "LA", "U1", "CN", "C1", "N1"
  )

  list(
    map = data.frame(
      bib = names(map),
      ris = unname(map),
      stringsAsFactors = FALSE
    ),
    order = tag_order
  )
}


# field name -> RIS tag for fields that were passed through untouched on read
# (DB, ID, M3, PT, Y2 ...). clean_ris_names() lower-cases names that are not
# tag-shaped, so "m3"/"y2" have to be recognised as well as "DB"/"ID"/"PT".
as_ris_tag <- function(field) {
  up <- toupper(field)
  ok <- grepl("^[A-Z][A-Z0-9]{1,3}$", up) &
    (grepl("[0-9]", field) | field == up)
  ifelse(ok, up, NA_character_)
}


# "362-91" -> c(startpage = "362", endpage = "91")
pages_to_tags <- function(value) {
  if (length(value) >= 2) {
    return(stats::setNames(value[1:2], c("startpage", "endpage")))
  }
  # a leading dash means "end page only" ("-218"), which is the only way to
  # record an end page with no start page
  end_only <- grepl("^\\s*[-\u2012-\u2015]", value)
  parts <- strsplit(value, "\\s*[-\u2012-\u2015]+\\s*")[[1]]
  parts <- parts[nzchar(parts)]
  if (length(parts) < 2) {
    if (length(parts) == 0) {
      return(stats::setNames(character(0), character(0)))
    }
    return(stats::setNames(parts, if (end_only) "endpage" else "startpage"))
  }
  stats::setNames(
    c(parts[1], paste(parts[-1], collapse = "-")),
    c("startpage", "endpage")
  )
}


# drop empties, optionally re-split collapsed fields, protect line structure
#
# Every field is split, not a whitelist: ris_to_df() joins with a delimiter
# that cannot occur in bibliographic text, so a value containing it can only
# have been produced by that join. fixed = TRUE is required, since the default
# delimiter contains the regex metacharacter "|".
clean_entry <- function(a, delimiter, resplit) {
  a <- a[!(tolower(names(a)) %in% c("label", "filename"))]
  a <- lapply(a, function(v) {
    v <- as.character(v)
    v <- v[!is.na(v)]
    v[nzchar(trimws(v))]
  })
  a <- a[lengths(a) > 0]
  if (resplit && nzchar(delimiter) && length(a) > 0) {
    a <- lapply(a, function(v) {
      if (length(v) == 1 && grepl(delimiter, v, fixed = TRUE)) {
        parts <- trimws(strsplit(v, delimiter, fixed = TRUE)[[1]])
        v <- parts[nzchar(parts)]
      }
      v
    })
  }
  lapply(a, function(v) gsub("[\r\n]+", " ", v))
}


# data.frame or ris_records -> plain list of named character vectors
prepare_entries <- function(x, delimiter, resplit) {
  if (inherits(x, "data.frame")) {
    cols <- colnames(x)
    labels <- if (any(cols == "label")) {
      as.character(x$label)
    } else {
      ris_index("ref", nrow(x))
    }
    entries <- lapply(seq_len(nrow(x)), function(i) {
      out <- lapply(cols, function(cl) as.character(x[[cl]][i]))
      names(out) <- cols
      out
    })
    names(entries) <- labels
  } else {
    entries <- unclass(x)
    if (is.null(names(entries))) {
      names(entries) <- ris_index("ref", length(entries))
    }
  }
  lapply(entries, clean_entry, delimiter = delimiter, resplit = resplit)
}


# one entry -> vector of RIS lines (ER included)
entry_to_ris <- function(
  a,
  lookup,
  order_tags,
  year_suffix,
  journal_from_position
) {
  if (length(a) == 0) {
    return(character(0))
  }

  # a journal that sits *before* the author/year block came from a title-block
  # tag (T2/T3) rather than from JF/JO - revtools' reader kept that positional
  # information even though it discarded the tag itself
  if (journal_from_position) {
    nm <- tolower(names(a))
    j <- which(nm == "journal")
    if (length(j) == 1 && !any(nm == "journal_secondary")) {
      anchors <- which(nm %in% c("author", "author_full", "year"))
      if (length(anchors) > 0 && j < min(anchors)) {
        names(a)[j] <- "journal_secondary"
      }
    }
  }

  z <- data.frame(
    field = rep(names(a), lengths(a)),
    value = unlist(a, use.names = FALSE),
    stringsAsFactors = FALSE
  )

  # pages -> startpage / endpage
  is_pages <- tolower(z$field) %in% c("pages", "page")
  if (any(is_pages)) {
    pg <- pages_to_tags(z$value[is_pages])
    z <- rbind(
      z[!is_pages, ],
      data.frame(
        field = names(pg),
        value = unname(pg),
        stringsAsFactors = FALSE
      )
    )[order(c(which(!is_pages), rep(which(is_pages)[1], length(pg)))), ]
  }

  # field name -> tag, falling back to pass-through tags (DB, ID, M3, PT ...)
  z$tag <- lookup$map$ris[match(tolower(z$field), tolower(lookup$map$bib))]
  na_tag <- is.na(z$tag)
  if (any(na_tag)) {
    z$tag[na_tag] <- as_ris_tag(z$field[na_tag])
    z <- z[!is.na(z$tag), ]
  }
  if (nrow(z) == 0) {
    return(character(0))
  }

  # Ovid writes year-only dates as "2020//"; the reader strips the "//"
  if (nzchar(year_suffix)) {
    yr <- which(z$tag %in% c("Y1", "PY") & grepl("^[0-9]{4}$", z$value))
    if (length(yr) > 0) {
      z$value[yr] <- paste0(z$value[yr], year_suffix)
    }
  }

  if (order_tags) {
    z <- z[order(match(z$tag, lookup$order), seq_len(nrow(z))), ]
  }
  # TY must come first: RIS readers (including read_ris) use the most common
  # opening tag to find record boundaries
  ty <- which(z$tag == "TY")
  if (length(ty) > 0 && ty[1] != 1) {
    z <- z[c(ty, setdiff(seq_len(nrow(z)), ty)), ]
  }

  c(paste0(z$tag, "  - ", z$value), "ER  -")
}


#' Write records to a RIS or BibTeX file
#'
#' Writes a data frame or `ris_records` object out as RIS or BibTeX.
#'
#' @param x A data frame (one row per record) or a `ris_records` object.
#' @param filename Path to write to.
#' @param format `"ris"` (the default) or `"bib"`.
#' @param dialect `"ovid"` (the default) writes `T1`/`A1`/`Y1`/`N2`/`JF`, the
#'   tags an Ovid or EndNote export uses, so a file read with [read_ris()] is
#'   written back with the tags it came in with. `"generic"` writes
#'   `TI`/`AU`/`PY`/`AB`/`JO`.
#' @param tag_map Optional named list or vector of `field = "TAG"` overrides,
#'   which take precedence over the dialect defaults.
#' @param delimiter The multi-value delimiter to split on. Defaults to
#'   [ris_sep()]. Only applied to data frame input, since a `ris_records`
#'   object already holds proper vectors. Split with `fixed = TRUE`, so this
#'   is a literal string rather than a regular expression.
#' @param order_tags If `TRUE` (the default), tags are written in a canonical
#'   order. If `FALSE`, fields keep the order they have in `x`.
#' @param journal_from_position If `TRUE`, a `journal` field appearing before
#'   the author/year block is written as `T3` rather than `JF`, recovering
#'   series and volume titles. Defaults to `FALSE`: this is only correct for
#'   records produced by revtools' reader. [read_ris()] keeps the original tag
#'   as the field name instead, so on its output this would relabel a correct
#'   `journal`.
#' @param year_suffix Appended to bare 4-digit years. Defaults to `"//"` for
#'   the Ovid dialect and `""` otherwise.
#' @param blank_line If `TRUE`, add an empty line after each `ER`.
#' @param eol Line ending. Defaults to `"\r\n"` for RIS and `"\n"` for BibTeX.
#'
#' @return The filename, invisibly.
#'
#' @details
#' Relative to revtools' `write_bibliography()`:
#'
#' * Tags are no longer stripped of digits, so `M3` and `Y2` survive rather
#'   than becoming `M` and `Y` and being dropped.
#' * Fields with no entry in the tag map are passed through if the field name
#'   is itself a RIS tag; anything genuinely unwritable raises one warning
#'   naming the fields.
#' * `issue` is mapped, single-value and non-numeric page fields are kept, and
#'   records are written with `TY` first and `ER` last.
#' * RIS is written with CRLF line endings and no quoting.
#'
#' @examples
#' df <- data.frame(
#'   label = "ref_1",
#'   type = "JOUR",
#'   title = "A study",
#'   author = "Smith, J. | Jones, A.",
#'   year = "2020",
#'   stringsAsFactors = FALSE
#' )
#'
#' f <- tempfile(fileext = ".ris")
#' write_ris(df, f)
#' cat(readLines(f), sep = "\n")
#' unlink(f)
#'
#' @seealso [read_ris()] to read files back in.
#'
#' @export
write_ris <- function(
  x,
  filename,
  format = "ris",
  dialect = "ovid",
  tag_map = NULL,
  delimiter = ris_sep(),
  order_tags = TRUE,
  journal_from_position = FALSE,
  year_suffix = NULL,
  blank_line = FALSE,
  eol = NULL
) {
  if (missing(filename)) {
    stop("argument 'filename' is missing, with no default")
  }
  if (
    !inherits(x, "ris_records") &&
      !inherits(x, "bibliography") &&
      !inherits(x, "data.frame")
  ) {
    stop(
      "write_ris only accepts objects of class 'data.frame' or 'ris_records'"
    )
  }
  format <- match.arg(tolower(format), c("ris", "bib"))
  dialect <- match.arg(tolower(dialect), c("ovid", "generic"))
  if (is.null(eol)) {
    eol <- if (format == "ris") "\r\n" else "\n"
  }
  if (is.null(year_suffix)) {
    year_suffix <- if (dialect == "ovid") "//" else ""
  }
  if (is.null(delimiter)) {
    delimiter <- ""
  }

  # values are only re-split when they were collapsed in the first place,
  # i.e. when x is a data.frame built by ris_to_df()
  resplit <- inherits(x, "data.frame")
  entries <- prepare_entries(x, delimiter, resplit)

  if (format == "bib") {
    # every multi-value field, author included, is joined with the shared
    # delimiter, which is what read_bib() splits on. revtools joined authors
    # with " and " and everything else with "; "; its reader never split on
    # "; ", so those values could not be read back.
    bib_sep <- if (nzchar(delimiter)) delimiter else "; "
    result <- lapply(entries, function(a) {
      a <- lapply(a, function(b) {
        if (length(b) > 1) {
          paste(b, collapse = bib_sep)
        } else {
          b
        }
      })
      paste0(names(a), "={", a, "},")
    })
    export <- unlist(
      lapply(
        seq_along(result),
        function(a, source, entry_names) {
          c(
            paste0("@ARTICLE{", entry_names[a], ","),
            source[[a]],
            "}",
            ""
          )
        },
        source = result,
        entry_names = names(entries)
      ),
      use.names = FALSE
    )
  }

  if (format == "ris") {
    lookup <- ris_write_tags(dialect)
    if (!is.null(tag_map)) {
      # user-supplied field -> tag mapping wins; keep defaults not overridden
      extra <- data.frame(
        bib = names(tag_map),
        ris = unname(unlist(tag_map)),
        stringsAsFactors = FALSE
      )
      keep <- !(tolower(lookup$map$bib) %in% tolower(extra$bib))
      lookup$map <- rbind(extra, lookup$map[keep, ])
      # new tags keep their canonical slot if they have one, otherwise they
      # are written after the tags that do
      lookup$order <- unique(c(lookup$order, extra$ris))
    }

    # warn once about anything that has no RIS representation
    all_fields <- setdiff(
      unique(unlist(lapply(entries, names))),
      c("pages", "page")
    )
    if (length(all_fields) > 0) {
      unmapped <- all_fields[
        is.na(lookup$map$ris[match(
          tolower(all_fields),
          tolower(lookup$map$bib)
        )]) &
          is.na(as_ris_tag(all_fields))
      ]
      if (length(unmapped) > 0) {
        warning(
          "no RIS tag for the following field(s), which were not exported: ",
          paste(unmapped, collapse = ", "),
          call. = FALSE
        )
      }
    }

    export <- unlist(
      lapply(
        entries,
        function(a) {
          lines <- entry_to_ris(
            a,
            lookup = lookup,
            order_tags = order_tags,
            year_suffix = year_suffix,
            journal_from_position = journal_from_position
          )
          if (blank_line) {
            c(lines, "")
          } else {
            lines
          }
        }
      ),
      use.names = FALSE
    )
  }

  con <- file(filename, open = "wb")
  on.exit(close(con))
  writeLines(export, con = con, sep = eol, useBytes = TRUE)
  invisible(filename)
}

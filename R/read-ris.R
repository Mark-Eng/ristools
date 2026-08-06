# ============================================================================
#  Reading bibliographic files
#
#  A RIS file becomes a data frame whose columns are the file's own tags, with
#  nothing renamed, merged or reordered, so it can be written back unchanged.
#
#  Semantic field naming (author/title/year/...), and support for reading
#  Medline and Web of Science exports, were removed in 0.3.0; see
#  inst/notes/reintroducing-semantic-fields.md before restoring either.
# ============================================================================

#' Read a RIS or BibTeX file
#'
#' Imports one or more bibliographic files into a data frame whose columns are
#' the file's own RIS tags.
#'
#' @param filename Path to a file, or a character vector of paths. Multiple
#'   files are read and combined, with a `filename` column recording the
#'   source of each record.
#' @param return_df If `TRUE` (the default), returns a data frame with one row
#'   per record. If `FALSE`, returns a `ris_records` object: a list with one
#'   element per record, each a named list of fields.
#' @param delimiter The string used to join multiple values in one field when
#'   `return_df = TRUE`. Defaults to [ris_sep()].
#' @param full_path Applies to multi-file reads. If `FALSE` (the default), the
#'   `filename` column holds the bare file name; if `TRUE`, the path as passed
#'   to `filename`. Reading files of the same name from more than one directory
#'   produces duplicate bare names, which is warned about — use `TRUE` there.
#'
#' @return A data frame with one column per RIS tag found in the input, or a
#'   `ris_records` list if `return_df = FALSE`.
#'
#' @details
#' Every field keeps the raw tag it was read under (`AU`, `TI`, `PY`, `KW`, …),
#' so the output mirrors the input file as closely as a table can: a file can be
#' read, inspected, edited and written back out with [write_ris()] with nothing
#' merged, renamed or reordered along the way. Tags that carry the same meaning
#' are *not* combined — a file using both `KW` and `DE` gets a column for each.
#' A tag that repeats within one record (two `AU` lines, several `KW` lines)
#' becomes a vector under that one tag, joined by `delimiter` in the data frame.
#'
#' Because the tag used for a given concept differs by source — the author is
#' `AU` in an EconLit export but `A1` in an Ovid one — the column names of two
#' files read this way can differ even where their content lines up. This suits
#' working with one file, or several from the same platform. Use
#' [ris_tag_lookup()] to look up what a tag conventionally means.
#'
#' A RIS tag is two characters, a capital followed by a capital or a digit, then
#' two spaces and a hyphen. A line not matching that is treated as a
#' continuation of the field above it, which is what makes wrapped keyword
#' blocks parse correctly. Records must be terminated by `ER`; a file without
#' one is rejected rather than guessed at. Web of Science (`.ciw`) and PubMed
#' (`.nbib`) exports tag their lines differently and are not supported.
#'
#' BibTeX is detected by content rather than extension: a file with more `{`
#' than `" - "` in its first 200 lines is read as BibTeX. Its columns are named
#' after its own field names (`author`, `title`, …), which are not RIS tags, so
#' there is no raw-tag form to preserve.
#'
#' @examples
#' f <- tempfile(fileext = ".ris")
#' writeLines(c(
#'   "TY  - JOUR",
#'   "T1  - A study of things",
#'   "A1  - Smith, John",
#'   "A1  - Jones, Mary",
#'   "Y1  - 2020//",
#'   "ER  - "
#' ), f)
#'
#' df <- read_ris(f)
#' colnames(df)
#' df$A1
#'
#' # one list element per record, with proper vectors rather than joined strings
#' recs <- read_ris(f, return_df = FALSE)
#' recs[[1]]$A1
#'
#' unlink(f)
#'
#' @seealso [write_ris()] to write files back out, [ris_to_df()] and
#'   [df_to_ris()] to convert between the two representations,
#'   [ris_tag_lookup()] for what a tag means.
#'
#' @export
read_ris <- function(
  filename,
  return_df = TRUE,
  delimiter = ris_sep(),
  full_path = FALSE
) {
  invisible(Sys.setlocale("LC_ALL", "C"))
  on.exit(invisible(Sys.setlocale("LC_ALL", "")))

  if (missing(filename)) {
    stop("filename is missing with no default")
  }
  file_check <- unlist(lapply(filename, file.exists))
  if (any(!file_check)) {
    stop("file not found")
  }

  if (length(filename) > 1) {
    result_list <- lapply(
      filename,
      function(a, df, sep) {
        read_ris_internal(a, df, sep)
      },
      df = return_df,
      sep = delimiter
    )
    names(result_list) <- ris_source_names(filename, full_path)
    if (return_df) {
      result <- merge_ris_columns(result_list)
      result$filename <- unlist(
        lapply(
          seq_len(length(result_list)),
          function(a, data) {
            rep(names(data)[a], nrow(data[[a]]))
          },
          data = result_list
        )
      )
      # rbind() inside merge_ris_columns() carries row names over from the
      # per-file frames, which leaves the source path in the row names of every
      # row. The filename column records provenance; the row names should just
      # number the rows.
      rownames(result) <- NULL
      return(result)
    } else {
      result <- do.call(c, result_list)
      return(result)
    }
  } else {
    return(read_ris_internal(filename, return_df, delimiter))
  }
}


# names for the filename column of a multi-file read. Bare file names are
# easier to read and to group by, but they are not unique across directories, so
# a collision is reported rather than silently de-duplicated: mangling one of
# them to "export.ris.1" would misreport which file a record came from, and the
# column exists to record exactly that.
ris_source_names <- function(filename, full_path) {
  if (full_path) {
    return(filename)
  }
  short <- basename(filename)
  if (anyDuplicated(short)) {
    clashing <- unique(short[duplicated(short)])
    warning(
      "the same file name appears in more than one directory (",
      paste(clashing, collapse = ", "),
      "), so the filename column cannot identify the source uniquely. ",
      "Use full_path = TRUE to record full paths.",
      call. = FALSE
    )
  }
  short
}


# underlying workhorse function
read_ris_internal <- function(
  filename,
  return_df = TRUE,
  delimiter = ris_sep()
) {
  z <- tryCatch(
    {
      scan(
        filename,
        sep = "\t",
        what = "character",
        quote = "",
        quiet = TRUE,
        blank.lines.skip = FALSE
      )
    },
    warning = function(w) {
      stop(
        "file import failed: data type not recognized by read_ris",
        call. = FALSE
      )
    },
    error = function(e) {
      stop(
        "file import failed: data type not recognized by read_ris",
        call. = FALSE
      )
    }
  )

  # Strip a byte order mark, before Encoding() reinterprets its bytes as
  # three latin1 characters and stops the first tag matching. Without this
  # the opening record loses its tag, so prep_ris() sees one fewer record
  # start than end. Affects every EBSCO export.
  if (length(z) > 0) {
    z[1] <- sub("^\xef\xbb\xbf", "", z[1], useBytes = TRUE)
  }

  # Mark the encoding rather than assuming latin1, which mojibakes every
  # non-ASCII character of a UTF-8 file ("socio-economic" with a U+2010
  # hyphen became "socioa€economic"). Ovid exports are pure ASCII, so the
  # assumption was invisible there; EBSCO exports are UTF-8.
  Encoding(z) <- if (isTRUE(all(validUTF8(z)))) "UTF-8" else "latin1"
  z <- gsub("<[[:alnum:]]{2}>", "", z) # remove errors from above process

  # detect whether file is bib-like or ris-like via the most common single
  # characters
  nrows <- min(c(200, length(z)))
  zsub <- z[seq_len(nrows)]
  n_brackets <- length(grep("\\{", zsub))
  n_dashes <- length(grep(" - ", zsub))
  if (n_brackets > n_dashes) {
    result <- read_bib(z, delimiter)
  } else {
    require_endrow(zsub)
    result <- parse_ris_raw(prep_ris(z))
  }

  if (return_df) {
    result <- ris_to_df(result, delimiter = delimiter)
  }
  return(result)
}


# combine data frames with differing columns, filling gaps with NA. Column
# order is the mean position each name occupies across the inputs.
merge_ris_columns <- function(x, y) {
  if (missing(x)) {
    stop("object x is missing with no default")
  }
  if (!inherits(x, "data.frame") && !inherits(x, "list")) {
    stop("object x must be either a data.frame or a list")
  }
  if (inherits(x, "data.frame")) {
    if (missing(y)) {
      stop("If x is a data.frame, then y must be supplied")
    }
    x <- list(x, y)
  } else {
    if (!all(unlist(lapply(x, function(a) inherits(a, "data.frame"))))) {
      stop("x must only contain data.frames")
    }
  }

  col_list <- lapply(x, colnames)
  col_names_all <- unique(unlist(col_list))
  col_lookup <- as.data.frame(
    lapply(
      col_list,
      function(a, lookup) {
        unlist(lapply(lookup, function(b) {
          if (any(a == b)) {
            which(a == b)
          } else {
            NA
          }
        }))
      },
      lookup = col_names_all
    )
  )
  colnames(col_lookup) <- seq_along(col_list)
  col_order <- apply(col_lookup, 1, function(a) mean(a, na.rm = TRUE))
  col_names_all <- col_names_all[order(col_order)]

  result_list <- lapply(
    x,
    function(a, cn) {
      missing_names <- !(cn %in% colnames(a))
      if (any(missing_names)) {
        new_names <- cn[missing_names]
        result <- data.frame(
          c(a, sapply(new_names, function(b) NA)),
          stringsAsFactors = FALSE
        )
        return(result[, cn])
      } else {
        return(a[, cn])
      }
    },
    cn = col_names_all
  )
  do.call(rbind, result_list)
}


# RIS records are terminated by "ER  - ". The specification requires it, every
# real exporter emits it, and split_ris_file() already refuses files without it.
# Earlier versions carried two fallbacks for records separated by a line of one
# repeated character, or by a blank line, for formats this package no longer
# reads. Both were untested, and the repeated-character test was itself broken
# (length(a > 6) is the line's character count, not a repeat count), so a file
# reaching them was parsed into something arbitrary rather than rejected. An
# explicit error beats a silent misparse.
require_endrow <- function(x) {
  if (!any(grepl("^ER", x))) {
    stop(
      "no 'ER' record terminator found in the first ",
      length(x),
      " lines: is this a RIS file? Web of Science (.ciw), PubMed (.nbib) and ",
      "blank-line-delimited formats are not supported.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


# The pattern that identifies a tag at the start of a line.
#
# A RIS tag is always two characters -- a capital followed by a capital or a
# digit -- then two spaces and a hyphen. Requiring that separator is what tells
# a tag from a continuation line, and it is enough on its own: no list of known
# tags is needed.
#
# Making the separator optional (as revtools did) misparsed every wrapped EBSCO
# keyword block. EBSCO breaks a multi-value KW field across lines without
# repeating the tag, so "E7 economies" matched as tag "E7" with text
# "economies" -- the keyword lost its first word, went into a bogus E7 field,
# and the following lines inherited E7 from the fill-forward below. A whole-line
# match such as "EKC" left no text at all and was dropped by the empty-row
# filter. See tests/testthat/test-tag-regex.R.
#
# The trailing space is optional at end of line, because write_ris() emits a
# bare "ER  -" and those files have to keep parsing.
#
# Other formats tag their lines differently -- Web of Science .ciw uses a bare
# single space ("AU Smith, J"), PubMed .nbib uses "PMID- " -- and are not read
# by this package. Supporting one means adding a pattern for it and selecting by
# format; the permissive pattern this package used to share between RIS and .ciw
# is what caused the keyword bug above, so it must never apply to .ris.
# See inst/notes/reintroducing-semantic-fields.md.
ris_tag_pattern <- function() {
  paste0(
    "^[[:upper:]][[:upper:][:digit:]]  - ",
    "|^[[:upper:]][[:upper:][:digit:]]  -$"
  )
}


# split raw RIS lines into a data frame of tag / text / row, filling tags
# forward across continuation lines
prep_ris <- function(z) {
  # detect tags
  tags <- regexpr(ris_tag_pattern(), perl = TRUE, z)
  z_dframe <- data.frame(
    text = z,
    row = seq_along(z),
    match_length = attr(tags, "match.length"),
    stringsAsFactors = FALSE
  )
  z_list <- split(z_dframe, z_dframe$match_length)
  z_list <- lapply(z_list, function(a) {
    n <- a$match_length[1]
    if (n < 0) {
      result <- data.frame(
        ris = "",
        text = a$text,
        row_order = a$row,
        stringsAsFactors = FALSE
      )
    } else {
      result <- data.frame(
        ris = sub("\\s{0,}-\\s{0,}|^\\s+|\\s+$", "", substr(a$text, 1, n)),
        text = gsub("^\\s+|\\s+$", "", substr(a$text, n + 1, nchar(a$text))),
        row_order = a$row,
        stringsAsFactors = FALSE
      )
    }
    return(result)
  })
  z_dframe <- do.call(rbind, z_list)
  z_dframe <- z_dframe[order(z_dframe$row), ]

  # Trim each record to its own tags: find the tag most records open with, and
  # keep only the lines from there to the closing "ER". This is what discards
  # any header or preamble a file carries ahead of its first record.
  z_dframe$ref <- c(
    0,
    cumsum(z_dframe$ris == "ER")[
      seq_len(nrow(z_dframe) - 1)
    ]
  ) # split by reference

  start_tags <- unlist(lapply(
    split(z_dframe$ris, z_dframe$ref),
    function(a) {
      a[which(a != "")[1]]
    }
  ))
  start_tags <- start_tags[!is.na(start_tags)]
  # A file whose lines carry no RIS tag at all has no record to open. This
  # catches a file that reaches here on the strength of an "ER" line while
  # tagging every other line some other way -- a Web of Science .ciw export, for
  # instance, whose tags are a bare two characters and a single space.
  if (length(start_tags) == 0) {
    stop(
      "no RIS tags found: is this a RIS file? A tag is two characters ",
      "(a capital, then a capital or a digit) followed by two spaces and a ",
      "hyphen, as in 'TY  - JOUR'. Web of Science (.ciw) and PubMed (.nbib) ",
      "exports tag their lines differently and are not supported.",
      call. = FALSE
    )
  }
  start_tag <- names(which.max(xtabs(~start_tags)))

  row_df <- data.frame(
    start = which(z_dframe$ris == start_tag),
    end = which(z_dframe$ris == "ER")
  )
  z_list <- apply(
    row_df,
    1,
    function(a) {
      c(a[1]:a[2])
    }
  )
  z_list <- lapply(
    z_list,
    function(a, lookup) {
      lookup[a, ]
    },
    lookup = z_dframe
  )
  z_dframe <- as.data.frame(
    do.call(rbind, z_list)
  )

  # cleaning
  z_dframe$ref <- c(
    0,
    cumsum(z_dframe$ris == "ER")[
      seq_len(nrow(z_dframe) - 1)
    ]
  ) # split by reference
  z_dframe <- z_dframe[which(z_dframe$text != ""), ] # remove empty rows
  z_dframe <- z_dframe[which(z_dframe$ris != "ER"), ] # remove end rows
  z_dframe$text <- trimws(z_dframe$text)

  # fill missing tags
  z_split <- split(z_dframe, z_dframe$ref)
  z_split <- lapply(z_split, function(a) {
    if (a$ris[1] == "") {
      a$ris[1] <- "ZZ"
    }
    accum_ris <- Reduce(c, a$ris, accumulate = TRUE)
    a$ris <- unlist(lapply(
      accum_ris,
      function(b) {
        good_vals <- which(b != "")
        b[good_vals[length(good_vals)]]
      }
    ))
    return(a)
  })
  z_dframe <- as.data.frame(
    do.call(rbind, z_split)
  )

  return(z_dframe)
}


# turn a prepped RIS data frame into a ris_records list, with no renaming or
# merging: every distinct tag in a record becomes its own field, under its own
# raw name, exactly as it appeared. A tag repeated within one record (two AU
# lines, several KW lines) becomes a vector under that tag.
parse_ris_raw <- function(x) {
  x_split <- split(x[c("ris", "text", "row_order")], x$ref)
  x_final <- lapply(x_split, function(a) {
    result <- split(a$text, a$ris)
    # fields are ordered by first appearance in the record
    entry_order <- a$row_order[match(names(result), a$ris)]
    result[order(entry_order)]
  })

  # Records are named by position. Earlier versions built an author/year/journal
  # label ("Smith_2020_JEco"), which required a full semantic parse of the file
  # purely to decide which tag was "the" author -- see
  # inst/notes/reintroducing-semantic-fields.md. The list is still named because
  # write_ris() uses these names as BibTeX citation keys.
  names(x_final) <- ris_index("ref", length(x_final))

  class(x_final) <- "ris_records"
  return(x_final)
}


read_bib <- function(x, delimiter = ris_sep()) {
  # which lines start with @article?
  group_vec <- rep(0, length(x))
  row_id <- which(regexpr("^@", x) == 1)
  group_vec[row_id] <- 1
  group_vec <- cumsum(group_vec)

  # work out row names
  ref_names <- gsub(".*\\{|,$", "", x[row_id])
  ref_type <- gsub(".*@|\\{.*", "", x[row_id])

  # split by reference
  x_split <- split(x[-row_id], group_vec[-row_id])
  length_vals <- unlist(lapply(x_split, length))
  x_split <- x_split[which(length_vals > 3)]

  x_final <- lapply(x_split, function(z) {
    # first use a stringent lookup term to locate only tagged rows
    delimiter_lookup <- regexpr(
      "^[[:blank:]]*([[:alnum:]]|[[:punct:]])+[[:blank:]]*=[[:blank:]]*\\{+",
      z
    )
    delimiter_rows <- which(delimiter_lookup != -1)
    other_rows <- which(delimiter_lookup == -1)
    delimiters <- data.frame(
      row = delimiter_rows,
      location = regexpr("=", z[delimiter_rows])
    )
    split_tags <- apply(
      delimiters,
      1,
      function(a, lookup) {
        c(
          row = as.numeric(a[1]),
          tag = substr(
            x = lookup[a[1]],
            start = 1,
            stop = a[2] - 1
          ),
          value = substr(
            x = lookup[a[1]],
            start = a[2] + 1,
            stop = nchar(lookup[a[1]])
          )
        )
      },
      lookup = z
    )
    entry_dframe <- rbind(
      as.data.frame(
        t(split_tags),
        stringsAsFactors = FALSE
      ),
      data.frame(
        row = other_rows,
        tag = NA,
        value = z[other_rows],
        stringsAsFactors = FALSE
      )
    )
    entry_dframe$row <- as.numeric(entry_dframe$row)
    entry_dframe <- entry_dframe[order(entry_dframe$row), c("tag", "value")]

    if (any(entry_dframe$value == "}")) {
      entry_dframe <- entry_dframe[
        seq_len(which(entry_dframe$value == "}")[1] - 1),
      ]
    }
    if (any(entry_dframe$value == "")) {
      entry_dframe <- entry_dframe[-which(entry_dframe$value == ""), ]
    }

    # remove whitespace
    entry_dframe <- as.data.frame(
      lapply(entry_dframe, trimws),
      stringsAsFactors = FALSE
    )
    # remove 1 or more opening brackets
    entry_dframe$value <- gsub("^\\{+", "", entry_dframe$value)
    # remove 1 or more closing brackets followed by 0+ punctuation marks
    entry_dframe$value <- gsub("\\}+[[:punct:]]*$", "", entry_dframe$value)

    # convert each entry to a list
    label_group <- rep(0, nrow(entry_dframe))
    tag_rows <- which(entry_dframe$tag != "")
    label_group[tag_rows] <- 1
    tag_names <- entry_dframe$tag[tag_rows]
    entry_list <- split(
      entry_dframe$value,
      cumsum(label_group) + 1
    )
    # clean_ris_names() rather than tolower(): tags such as DB, ID and M3
    # keep their case, so they are still recognisable as ris tags on export
    names(entry_list) <- clean_ris_names(
      gsub("^\\s+|\\s+$", "", tag_names)
    )
    entry_list <- lapply(entry_list, function(a) {
      paste(a, collapse = " ")
    })
    # every multi-value field, author included, uses the shared delimiter -
    # authors are not split on " and ", which occurs inside real author
    # strings and inside other field values, and so could never be inverted
    entry_list <- lapply(entry_list, function(a) {
      if (length(a) == 1 && grepl(delimiter, a, fixed = TRUE)) {
        a <- strsplit(a, delimiter, fixed = TRUE)[[1]]
      }
      return(a)
    })
    return(entry_list)
  })

  # add type, unless the entry already carries one (which it does if the file
  # was written from a record set that had a 'type' field)
  x_final <- lapply(
    seq_len(length(x_final)),
    function(a, type, data) {
      if (any(names(data[[a]]) == "type")) {
        data[[a]]
      } else {
        c(type = type[a], data[[a]])
      }
    },
    type = ref_type,
    data = x_final
  )

  names(x_final) <- ref_names
  class(x_final) <- "ris_records"
  return(x_final)
}
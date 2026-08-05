# ============================================================================
#  Reading bibliographic files
#
#  Fidelity-preserving replacement for revtools 0.4.1's read_bibliography()
#  and its internals. The losses fixed here are documented per-function below
#  and summarised in README.md.
# ============================================================================

#' Read a RIS, BibTeX, Medline or Web of Science file
#'
#' Imports one or more bibliographic files, detecting the format from their
#' contents.
#'
#' @param filename Path to a file, or a character vector of paths. Multiple
#'   files are read and combined, with a `filename` column recording the
#'   source of each record.
#' @param return_df If `TRUE` (the default), returns a data frame with one row
#'   per record. If `FALSE`, returns a `ris_records` object: a list with one
#'   element per record, each a named list of fields.
#' @param delimiter The string used to join multiple values in one field when
#'   `return_df = TRUE`. Defaults to [ris_sep()].
#' @param rename_columns If `FALSE` (the default), fields keep the raw tag
#'   they were read under (`AU`, `TI`, `PY`, `KW`, …) — one column per tag,
#'   exactly as the file has it, with no merging of tags that mean the same
#'   thing. If `TRUE`, fields are renamed and merged into the semantic names
#'   this package used by default before 0.2.0 (`author`, `title`, `year`,
#'   `keywords`, …); see Details.
#'
#' @return A data frame, or a `ris_records` list if `return_df = FALSE`.
#'
#' @details
#' Format detection is by content, not extension: a file with more `{` than
#' `" - "` in its first 200 lines is treated as BibTeX, otherwise as RIS. A
#' RIS-like file containing a `PMID` tag is read as Medline; a `.ciw` file is
#' read with Web of Science tags.
#'
#' **`rename_columns = FALSE` (the default)** keeps every field under the raw
#' tag it was read from, so the output mirrors the input file as closely as
#' possible: a record can be inspected, edited as a data frame, and written
#' back out with [write_ris()] with nothing merged or renamed along the way.
#' A tag that repeats within one record (two `AU` lines, several `KW` lines)
#' becomes a vector under that one tag. Because the tag used for the same
#' concept can differ by source (`author` is `AU` in an EconLit export but
#' `A1` in an Ovid one), the column names of two files read this way can
#' differ even when their content lines up conceptually. BibTeX input is
#' unaffected by `rename_columns`, since its field names (`author`, `title`,
#' …) are not RIS tags to begin with.
#'
#' **`rename_columns = TRUE`** merges tags that carry the same meaning into a
#' single semantically named column:
#'
#' * `author` from whichever of `AU`/`A1`/`A2`/… occurs most often in the file;
#'   any other author tag keeps its own name.
#' * `journal` from the first of `JO`/`T2`/`T3`/`SO`/`JT`/`JF`/`JA` present;
#'   the others again keep their own names.
#' * `pages` from `SP`/`BP` and `EP` joined as `"419-41"`. An end page with no
#'   start page becomes `"-218"`.
#' * `year`, `title`, `keywords`, `abstract`, `doi`, `issn` and the rest from
#'   the mapping [ris_tag_lookup()] returns.
#'
#' This is useful when combining files from several sources, where the same
#' concept arrives under a different tag in each. Note that the merge is not
#' reversible: once two tags become one column, [write_ris()] cannot tell which
#' value came from which, so a file read this way and written back out may not
#' use the tags it came in with.
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
#' df$A1
#'
#' df2 <- read_ris(f, rename_columns = TRUE)
#' df2$author
#'
#' unlink(f)
#'
#' @seealso [write_ris()] to write files back out, [ris_to_df()] and
#'   [df_to_ris()] to convert between the two representations.
#'
#' @export
read_ris <- function(
  filename,
  return_df = TRUE,
  delimiter = ris_sep(),
  rename_columns = FALSE
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
      function(a, df, sep, rename) {
        read_ris_internal(a, df, sep, rename)
      },
      df = return_df,
      sep = delimiter,
      rename = rename_columns
    )
    names(result_list) <- filename
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
      if (any(colnames(result) == "label")) {
        result$label <- make.unique(result$label)
      }
      return(result)
    } else {
      result <- do.call(c, result_list)
      return(result)
    }
  } else {
    return(
      read_ris_internal(filename, return_df, delimiter, rename_columns)
    )
  }
}


# underlying workhorse function
read_ris_internal <- function(
  filename,
  return_df = TRUE,
  delimiter = ris_sep(),
  rename_columns = FALSE
) {
  if (grepl(".csv$", filename)) {
    result <- read_ris_csv(filename)
    if (!return_df) {
      # read_ris_csv() has already normalised author delimiters to the shared
      # delimiter, so the same value splits every field here
      result <- df_to_ris(result, delimiter = delimiter)
    }
  } else {
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
      result <- read_bib(z, delimiter) # simple case - no further work needed
    } else {
      # ris format can be inconsistent; custom code needed
      if (grepl(".ciw$", filename)) {
        tag_type <- "wos"
      } else {
        tag_type <- "ris"
      }
      z_dframe <- prep_ris(z, detect_delimiter(zsub), tag_type)
      is_medline <- any(z_dframe$ris == "PMID")
      if (rename_columns) {
        if (is_medline) {
          result <- read_medline(z_dframe)
        } else {
          result <- parse_ris_tags(z_dframe, tag_type)
        }
      } else {
        result <- parse_ris_raw(z_dframe, tag_type, is_medline)
      }
    }
    if (return_df) {
      result <- ris_to_df(result, delimiter = delimiter)
    }
  }
  return(result)
}


#' Read a CSV-format bibliography
#'
#' Reads a csv of records into a data frame, cleaning its column names to match
#' the conventions the rest of the package uses.
#'
#' @param filename Path to a csv file.
#'
#' @return A data frame with one row per record.
#'
#' @details
#' Column names are lower-cased and stripped of punctuation, except names that
#' are already RIS tags, which keep their case.
#'
#' A `label` column is added unless the first column is already called `label`,
#' or can serve as one: the existing first column is left in place as the
#' record identifier if its values are unique and it is not named `author`,
#' `title`, `year` or `journal`. Otherwise sequential labels come from
#' [ris_index()].
#'
#' An `author` column is normalised to use [ris_sep()] between names, so that a
#' csv agrees with files read by [read_ris()]. The separator is inferred for the
#' column as a whole rather than row by row: if *every* value uses `" and "`,
#' `" AND "` or `" & "`, those are replaced; otherwise commas followed by a word
#' of two or more letters are treated as the separator. A column that already
#' uses the delimiter throughout is left untouched. Other multi-value fields are
#' expected to use the delimiter already.
#'
#' @examples
#' f <- tempfile(fileext = ".csv")
#' write.csv(
#'   data.frame(
#'     title = c("A study", "Another study"),
#'     author = c("Smith, J. and Jones, A.", "Black, K. and White, L."),
#'     year = c(2020, 2021)
#'   ),
#'   f,
#'   row.names = FALSE
#' )
#'
#' df <- read_ris_csv(f)
#' df$label
#' df$author
#'
#' unlink(f)
#'
#' @seealso [read_ris()] for RIS, BibTeX, Medline and Web of Science files.
#'
#' @export
read_ris_csv <- function(filename) {
  data <- utils::read.csv(filename, stringsAsFactors = FALSE)
  colnames(data) <- clean_ris_names(colnames(data))
  if (colnames(data)[1] != "label") {
    if (
      length(unique(data[, 1])) < nrow(data) ||
        any(c("author", "title", "year", "journal") == colnames(data)[1])
    ) {
      data <- data.frame(
        label = ris_index("ref", nrow(data)),
        data,
        stringsAsFactors = FALSE
      )
    }
  }
  if (any(colnames(data) == "author")) {
    data$author <- clean_author_delimiters(data$author)
  }
  return(data)
}


# normalise author-name delimiters in csv input to the shared delimiter, so a
# csv column agrees with the rest of the read path. A column that already uses
# the delimiter is left alone.
clean_author_delimiters <- function(x, delimiter = ris_sep()) {
  already <- grepl(delimiter, x, fixed = TRUE)
  if (all(already | is.na(x))) {
    return(x)
  }
  if (all(grepl("\\sand\\s|\\sAND\\s|\\s&\\s", x))) {
    # "A and B", "A AND B", "A & B" -> "A | B"
    x <- gsub("\\s+(and|AND)\\s+|\\s+&\\s+", delimiter, x)
  } else {
    # comma-separated names: "Smith, J., Jones, A." -> split before a word of
    # 2+ letters
    x <- gsub(
      ",(?=\\s[[:alpha:]]{2,})",
      sub("\\s+$", "", delimiter),
      x,
      perl = TRUE
    )
  }
  return(x)
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


rollingsum <- function(a, n = 2L) {
  utils::tail(
    cumsum(a) - cumsum(c(rep(0, n), utils::head(a, -n))),
    -n + 1
  )
}


# detect delimiters between references, starting with strings that start "ER"
detect_delimiter <- function(x) {
  if (any(grepl("^ER", x))) {
    delimiter <- "endrow"
  } else {
    # special break: same character repeated >6 times, no other characters
    char_list <- strsplit(x, "")
    char_break_test <- unlist(
      lapply(char_list, function(a) {
        length(unique(a)) == 1 & length(a > 6)
      })
    )
    if (any(char_break_test)) {
      delimiter <- "character"
    } else {
      # use space as a ref break (last choice)
      space_break_check <- unlist(lapply(
        char_list,
        function(a) {
          all(a == "" | a == " ")
        }
      ))
      if (any(space_break_check)) {
        delimiter <- "space"
      } else {
        stop("import failed: unknown reference delimiter")
      }
    }
  }
  return(delimiter)
}


# the pattern that identifies a tag at the start of a line
#
# A RIS tag is always two characters -- a capital followed by a capital or a
# digit -- then two spaces and a hyphen. The original pattern made the
# separator optional (`-{0,2}\s{0,}`), so a wrapped EBSCO keyword line matched
# as a tag. EBSCO breaks a multi-value KW field across lines without repeating
# the tag, and any keyword whose first word looks like a tag was then
# misparsed: "E7 economies" became tag "E7" with text "economies", so the
# keyword was truncated and filed under a bogus "E7" field, and the following
# keyword lines inherited "E7" from the fill-forward below. A whole-line match
# such as "EKC" or "GHG" left no text at all and was dropped outright by the
# empty-row filter. Requiring the separator is enough on its own to tell a tag
# from a keyword; no list of known tags is needed.
#
# The trailing space is optional at end of line, because write_ris() emits a
# bare "ER  -" and those files have to keep parsing.
#
# Web of Science .ciw files use a different form entirely -- a bare single
# space and no hyphen, as in "AU Smith, J" -- which the strict pattern matches
# not at all, so they keep the original permissive one. Adding a pattern per
# format is the way to support other dialects (.nbib and its "PMID- " tags)
# later.
ris_tag_pattern <- function(tag_type = "ris") {
  if (identical(tag_type, "ris")) {
    paste0(
      "^[[:upper:]][[:upper:][:digit:]]  - ",
      "|^[[:upper:]][[:upper:][:digit:]]  -$"
    )
  } else {
    "^([[:upper:]]{2,4}|[[:upper:]]{1}[[:digit:]]{1})\\s{0,}-{0,2}\\s{0,}"
  }
}


# split raw RIS lines into a data frame of tag / text / row, filling tags
# forward across continuation lines
prep_ris <- function(z, delimiter, tag_type = "ris") {
  # detect tags
  tags <- regexpr(ris_tag_pattern(tag_type), perl = TRUE, z)
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

  # replace tag information for delimiter == character | space
  if (delimiter == "character") {
    # i.e. a single character repeated many times
    z_dframe$ris[which(
      unlist(lapply(
        strsplit(z, ""),
        function(a) {
          length(unique(a)) == 1 & length(a > 6)
        }
      ))
    )] <- "ER"
  }
  if (delimiter == "space") {
    z_dframe$ris[which(z_dframe$ris == "" & z_dframe$text == "")] <- "ER"
    # ensure multiple consecutive empty rows are removed
    z_rollsum <- rollingsum(z_dframe$ris == "ER")
    if (any(z_rollsum > 1)) {
      z_dframe <- z_dframe[which(z_rollsum <= 1), ]
    }
  }
  if (delimiter == "endrow") {
    # work out what most common starting tag is
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
  }

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


read_medline <- function(x) {
  x_merge <- merge(
    x,
    ris_tag_lookup(type = "medline"),
    by = "ris",
    all.x = TRUE,
    all.y = FALSE
  )
  x_merge <- x_merge[order(x_merge$row_order), ]

  # convert into a list, where each reference is a separate entry
  x_split <- split(x_merge[c("bib", "text")], x_merge$ref)
  x_final <- lapply(x_split, function(a) {
    result <- split(a$text, a$bib)
    if (any(names(result) == "abstract")) {
      result$abstract <- paste(result$abstract, collapse = " ")
    }
    if (any(names(result) == "title")) {
      if (length(result$title) > 1) {
        result$title <- paste(result$title, collapse = " ")
      }
    }
    if (any(names(result) == "term_other")) {
      names(result)[which(names(result) == "term_other")] <- "keywords"
    }
    if (any(names(result) == "date_published")) {
      result$year <- substr(result$date_published, start = 1, stop = 4)
    }
    if (any(names(result) == "article_id")) {
      doi_check <- grepl("doi", result$article_id)
      if (any(doi_check)) {
        result$doi <- strsplit(result$article_id[which(doi_check)], " ")[[1]][1]
      }
    }
    return(result)
  })

  names(x_final) <- unlist(lapply(x_final, function(a) {
    a$pubmed_id
  }))
  class(x_final) <- "ris_records"
  return(x_final)
}


# generate a unique label per entry, using as much author & year data as
# possible
generate_ris_names <- function(x) {
  nonunique_names <- unlist(lapply(x, function(a) {
    name_vector <- rep("", 3)
    if (any(names(a) == "author")) {
      name_vector[1] <- strsplit(a$author[1], ",")[[1]][1]
    }
    if (any(names(a) == "year")) {
      name_vector[2] <- a$year[1]
    }
    if (any(names(a) == "journal")) {
      journal_info <- strsplit(a$journal, " ")[[1]]
      name_vector[3] <- paste(
        substr(journal_info, 1, min(nchar(journal_info), 4)),
        collapse = ""
      )
    }
    name_vector <- name_vector[which(name_vector != "")]
    if (length(name_vector) == 0) {
      return("ref")
    } else {
      return(paste(name_vector, collapse = "_"))
    }
  }))

  # where this is not possible, give a 'ref1' style result
  if (any(nonunique_names == "ref")) {
    rows_tr <- which(nonunique_names == "ref")
    nonunique_names[rows_tr] <- ris_index("ref", length(rows_tr))
  }

  # ensure names are unique
  if (length(unique(nonunique_names)) < length(nonunique_names)) {
    nonunique_names <- make.unique(nonunique_names, sep = "_")
  }

  return(nonunique_names)
}


# turn a prepped RIS data frame into a ris_records list. Named to distinguish
# it from the user-facing read_ris(); it takes the output of prep_ris(), not a
# filename.
parse_ris_tags <- function(x, tag_type = "ris") {
  # merge data with lookup info, to provide bib-style tags
  x_merge <- merge(
    x,
    ris_tag_lookup(type = tag_type),
    by = "ris",
    all.x = TRUE,
    all.y = FALSE
  )
  x_merge <- x_merge[order(x_merge$row_order), ]

  # find a way to store missing .bib data rather than discard
  if (any(is.na(x_merge$bib))) {
    rows_tr <- which(is.na(x_merge$bib))
    x_merge$bib[rows_tr] <- x_merge$ris[rows_tr]
    if (all(is.na(x_merge$row_order))) {
      start_val <- 0
    } else {
      start_val <- max(x_merge$row_order, na.rm = TRUE)
    }
    x_merge$row_order[rows_tr] <- as.numeric(
      as.factor(x_merge$ris[rows_tr])
    ) +
      start_val
  }

  # method to systematically search for year data
  year_check <- regexpr("^\\d{4}$", x_merge$text)
  if (any(year_check > 0)) {
    check_rows <- which(year_check > 0)
    year_strings <- as.numeric(x_merge$text[check_rows])

    # for entries with a bib entry labelled year, check there aren't multiple
    if (any(x_merge$bib[check_rows] == "year", na.rm = TRUE)) {
      # check for repeated year information
      year_freq <- xtabs(~ref, data = x_merge[which(x_merge$bib == "year"), ])
      if (any(year_freq > 1)) {
        year_df <- x_merge[which(x_merge$bib == "year"), ]
        year_list <- split(nchar(year_df$text), year_df$ris)
        year_4 <- sqrt((4 - unlist(lapply(year_list, mean)))^2)
        # rename bib entries with >4 characters to 'year_additional'
        incorrect_rows <- which(
          x_merge$ris != names(which.min(year_4)[1]) &
            x_merge$bib == "year"
        )
        x_merge$bib[incorrect_rows] <- "year_additional"
      }
    } else {
      # only tags that carry no other meaning are candidates for the year
      # tag: without the third condition a file in which >90% of (e.g.)
      # start pages are 4 digits long has its page tag relabelled 'year'
      possible_rows <- which(
        year_strings > 0 &
          year_strings <= as.numeric(format(Sys.Date(), "%Y")) + 1 &
          x_merge$bib[check_rows] == x_merge$ris[check_rows]
      )
      if (length(possible_rows) > 0) {
        tag_frequencies <- as.data.frame(
          xtabs(~ x_merge$ris[check_rows[possible_rows]]),
          stringsAsFactors = FALSE
        )
        colnames(tag_frequencies) <- c("tag", "n")
        # what proportion of references carry year data in each tag?
        tag_frequencies$prop <- tag_frequencies$n / (max(x_merge$ref) + 1)
        if (any(tag_frequencies$prop > 0.9)) {
          year_tag <- tag_frequencies$tag[which.max(tag_frequencies$prop)]
          rows_tr <- which(x_merge$ris == year_tag)
          x_merge$bib[rows_tr] <- "year"
          x_merge$row_order[rows_tr] <- 3
        }
      }
    }
  }

  # ensure author data from a single ris tag
  if (any(x_merge$bib == "author")) {
    lookup.tags <- xtabs(~ x_merge$ris[which(x_merge$bib == "author")])
    if (length(lookup.tags) > 1) {
      replace_tags <- names(which(lookup.tags < max(lookup.tags)))
      replace_rows <- which(x_merge$ris %in% replace_tags)
      x_merge$bib[replace_rows] <- x_merge$ris[replace_rows]
      if (all(is.na(x_merge$row_order))) {
        start_val <- 0
      } else {
        start_val <- max(x_merge$row_order, na.rm = TRUE)
      }
      x_merge$row_order[replace_rows] <- start_val +
        as.numeric(
          as.factor(x_merge$ris[replace_rows])
        )
    }
  }

  # convert into a list, where each reference is a separate entry
  x_split <- split(x_merge[c("bib", "ris", "text", "row_order")], x_merge$ref)

  x_final <- lapply(x_split, function(a) {
    result <- split(a$text, a$bib)
    # YEAR
    # reduced to the 4-digit year, as downstream code expects, but a value
    # that contains no 4-digit year is kept rather than blanked
    if (any(names(result) == "year")) {
      year_check <- regexpr("\\d{4}", result$year)
      if (any(year_check > 0)) {
        keep <- which(year_check > 0)[1]
        result$year <- substr(
          x = result$year[keep],
          start = year_check[keep],
          stop = year_check[keep] + 3
        )
      }
    }
    # TITLE
    if (any(names(result) == "title")) {
      if (length(result$title) > 1) {
        if (result$title[1] == result$title[2]) {
          result$title <- result$title[1]
        } else {
          result$title <- paste(result$title, collapse = " ")
        }
      }
      # titles are left exactly as imported: stripping the final full stop
      # removed the last character of titles ending in "U.S.", "D.C." etc.
    }
    # JOURNAL
    # JO/T2/T3/SO/JT/JF/JA all map to 'journal'. The first of those tags to
    # appear supplies 'journal'; any others keep their own tag as a field
    # name, so no value is merged into a "journal_secondary" string and the
    # tag it came from is recoverable. Punctuation is left as imported.
    if (any(names(result) == "journal")) {
      journal_rows <- which(a$bib == "journal")
      journal_tags <- a$ris[journal_rows]
      result$journal <- unique(
        a$text[journal_rows][journal_tags == journal_tags[1]]
      )
      other_rows <- journal_rows[journal_tags != journal_tags[1]]
      if (length(other_rows) > 0) {
        extra <- split(a$text[other_rows], a$ris[other_rows])
        result <- c(result, extra[!(names(extra) %in% names(result))])
      }
    }
    # ABSTRACT
    # was length(result$abstract > 1), which is always 1, so every record
    # without an abstract had an empty one added
    if (length(result$abstract) > 1) {
      result$abstract <- paste(result$abstract, collapse = " ")
    }
    # PAGE NUMBER
    # SP/BP (start) and EP (end) all map to 'pages'. Order is taken from the
    # tag rather than from sort(), which reversed ranges whose end page is
    # abbreviated ("419" + "41" became "41-419"). An end page with no start
    # page keeps a leading dash ("-218") so the two remain distinguishable.
    if (any(names(result) == "pages")) {
      page_rows <- which(a$bib == "pages")
      start_pages <- a$text[page_rows][a$ris[page_rows] %in% c("SP", "BP")]
      end_pages <- a$text[page_rows][a$ris[page_rows] == "EP"]
      if (length(start_pages) + length(end_pages) == 0) {
        result$pages <- paste(result$pages, collapse = "-")
      } else {
        result$pages <- paste0(
          paste(start_pages, collapse = "-"),
          if (length(end_pages) > 0) {
            paste0("-", paste(end_pages, collapse = "-"))
          } else {
            ""
          }
        )
      }
    }
    # fields are returned in the order they appeared in the file. The old
    # version used unlist(lapply(...)), which silently dropped a field
    # whenever a name could not be matched (the vector came back short, so
    # order() indexed past the end of the list)
    entry_rows <- match(names(result), a$bib)
    if (any(is.na(entry_rows))) {
      entry_rows[is.na(entry_rows)] <- match(
        names(result)[is.na(entry_rows)],
        a$ris
      )
    }
    entry_order <- a$row_order[entry_rows]
    entry_order[is.na(entry_order)] <- max(a$row_order, na.rm = TRUE) + 1
    final_result <- result[order(entry_order)]

    return(final_result)
  })

  names(x_final) <- generate_ris_names(x_final)
  class(x_final) <- "ris_records"
  return(x_final)
}


# turn a prepped RIS/Medline/WoS data frame into a ris_records list, with no
# renaming or merging: every distinct tag in a record becomes its own field,
# under its own raw name, exactly as it appeared. A tag repeated within one
# record (two AU lines, several KW lines) becomes a vector under that tag.
#
# This is deliberately a separate function from parse_ris_tags() rather than
# a rename step applied to its output: several of that function's semantic
# fields (author, journal, pages) are built by merging more than one tag's
# values (SP + EP into one "419-41" pages string; the first journal-mapped tag
# found wins "journal"), and once merged there is no way back to which tag
# supplied which part. Reversing that merge would need the same winner/loser
# bookkeeping that created it, for no benefit over never merging at all.
parse_ris_raw <- function(x, tag_type = "ris", is_medline = FALSE) {
  x_split <- split(x[c("ris", "text", "row_order")], x$ref)
  x_final <- lapply(x_split, function(a) {
    result <- split(a$text, a$ris)
    # fields are ordered by first appearance in the record, matching
    # parse_ris_tags()'s ordering
    entry_order <- a$row_order[match(names(result), a$ris)]
    result[order(entry_order)]
  })

  # record labels still need "the" author/year/journal (or, for Medline, the
  # PMID), which only the semantic parse can reliably pick (e.g. preferring AU
  # over a less-frequent A1, or the first-occurring journal tag rather than
  # whichever the lookup table happens to list first) -- so labels are
  # generated from a throwaway semantic parse, discarding everything except
  # the name it produces. The data returned to the caller is untouched by
  # this.
  names(x_final) <- if (is_medline) {
    vapply(x_final, function(a) a$PMID[1], character(1))
  } else {
    generate_ris_names(parse_ris_tags(x, tag_type))
  }

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
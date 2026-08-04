# ============================================================================
#  Converting between record lists and data frames
#
#  These were S3 methods (as.data.frame.bibliography, as.bibliography) on a
#  class owned by revtools. They are plain functions here: overriding another
#  package's registered S3 methods makes behaviour depend on package load
#  order, and ristools owns neither the generic nor the original class.
# ============================================================================

#' Convert a record list to a data frame
#'
#' Collapses a `ris_records` list into a data frame with one row per record,
#' joining multi-value fields with `delimiter`.
#'
#' @param x A `ris_records` object, as returned by [read_ris()] with
#'   `return_df = FALSE`.
#' @param delimiter The string used to join multiple values in one field.
#'   Defaults to [ris_sep()].
#'
#' @return A data frame with a `label` column followed by one column per field
#'   found anywhere in `x`. Records lacking a field get `NA`.
#'
#' @details
#' The conversion is lossless and is reversed exactly by [df_to_ris()],
#' because the default delimiter cannot occur in bibliographic text. Fields
#' whose names are short (fewer than 3 characters, i.e. raw RIS tags) are
#' placed after the named fields.
#'
#' @examples
#' recs <- structure(
#'   list(ref_1 = list(
#'     title = "A study",
#'     author = c("Smith, J.", "Jones, A.")
#'   )),
#'   class = "ris_records"
#' )
#' ris_to_df(recs)
#'
#' @seealso [df_to_ris()] for the inverse.
#'
#' @export
ris_to_df <- function(x, delimiter = ris_sep()) {
  cols <- unique(unlist(lapply(x, names)))

  # fix bug where ris tags get placed first if they appear before bib tags
  col_n <- nchar(cols)
  if (any(col_n < 3)) {
    cols <- cols[c(which(col_n >= 3), which(col_n < 3))]
  }

  x_list <- lapply(
    x,
    function(a, cols) {
      result <- lapply(
        cols,
        function(b, lookup) {
          if (any(names(lookup) == b)) {
            data_tr <- lookup[[b]]
            if (length(data_tr) > 1) {
              data_tr <- paste0(data_tr, collapse = delimiter)
            }
            return(data_tr)
          } else {
            return(NA)
          }
        },
        lookup = a
      )
      names(result) <- cols
      return(
        as.data.frame(
          result,
          stringsAsFactors = FALSE
        )
      )
    },
    cols = cols
  )

  x_dframe <- data.frame(
    label = make.names(names(x_list), unique = TRUE),
    do.call(rbind, x_list),
    stringsAsFactors = FALSE
  )
  rownames(x_dframe) <- NULL
  colnames(x_dframe) <- clean_ris_names(colnames(x_dframe))
  return(x_dframe)
}


#' Convert a data frame to a record list
#'
#' Splits a data frame of records into a `ris_records` list, splitting
#' multi-value fields on `delimiter`.
#'
#' @param x A data frame with one row per record. A `label` column, if
#'   present, supplies the names of the result and is not treated as a field.
#' @param delimiter The string on which to split multi-value fields. Defaults
#'   to [ris_sep()]. Split with `fixed = TRUE`, so this is a literal string
#'   rather than a regular expression.
#'
#' @return A `ris_records` object: a named list with one element per record,
#'   each a named list of fields.
#'
#' @details
#' *Every* field is split, not just `author` and `keywords`. Because the
#' default delimiter cannot occur in bibliographic text, a value containing it
#' can only have been produced by [ris_to_df()], so splitting unconditionally
#' is safe and no field needs special handling.
#'
#' Columns for which a record has no value are dropped rather than kept as
#' `NA`, so `is.null(x[[i]]$abstract)` means what it says.
#'
#' @examples
#' df <- data.frame(
#'   label = "ref_1",
#'   title = "A study",
#'   author = "Smith, J. | Jones, A.",
#'   stringsAsFactors = FALSE
#' )
#' recs <- df_to_ris(df)
#' recs$ref_1$author
#'
#' @seealso [ris_to_df()] for the inverse.
#'
#' @export
df_to_ris <- function(x, delimiter = ris_sep()) {
  if (!inherits(x, "data.frame")) {
    stop("df_to_ris can only be called for objects of class 'data.frame'")
  }

  # get labels for each entry
  x_cols <- colnames(x)
  if (any(x_cols == "label")) {
    label_col <- which(x_cols == "label")
    label_vec <- as.character(x[, label_col])
    x <- x[, -label_col, drop = FALSE]
  } else {
    label_vec <- ris_index("ref", nrow(x))
  }

  x_list <- lapply(
    split(x, seq_len(nrow(x))),
    function(a) {
      a <- as.list(a)
      # every field is split, not just author & keywords: the delimiter
      # cannot occur in bibliographic text, so a value containing it can
      # only have been joined by ris_to_df()
      a <- lapply(a, function(b) {
        b <- as.character(b)
        if (length(b) == 1 && !is.na(b) && grepl(delimiter, b, fixed = TRUE)) {
          b <- strsplit(b, delimiter, fixed = TRUE)[[1]]
        }
        return(b)
      })
      # columns this entry has no value for are dropped rather than kept as
      # NA, so that is.null(a$abstract) means what it says
      a <- a[
        !unlist(lapply(a, function(b) {
          all(is.na(b))
        }))
      ]
      return(a)
    }
  )
  names(x_list) <- label_vec
  class(x_list) <- "ris_records"
  return(x_list)
}


# clean up column names. Not exported: it would mask janitor::clean_names()
# for anyone loading both packages, and it is only used internally.
clean_ris_names <- function(x) {
  x <- sub("^(X|Y|Z)\\.+", "", x) # remove leading X
  x <- sub("^[[:punct:]]*", "", x) # leading punctuation
  x <- sub("[[:punct:]]*$", "", x) # trailing punctuation
  x <- gsub("\\.+", "_", x) # replace 1 or more dots with underscore
  # ris tags keep their case; unlike revtools this includes tags that contain
  # a digit (M3, Y2, U1), which were being lower-cased
  not_tags <- !grepl("^[[:upper:]][[:upper:][:digit:]]{1,3}$", x)
  x[not_tags] <- tolower(x[not_tags])
  x <- sub("authors", "author", x) # remove plural authors
  x <- make.unique(x, sep = "_") # ensure uniqueness
  return(x)
}

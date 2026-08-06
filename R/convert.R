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
#' @return A data frame with one column per field found anywhere in `x`, in the
#'   order fields are first seen. Records lacking a field get `NA`. The record
#'   names of `x` are not added as a column; use `names(x)` for those.
#'
#' @details
#' The round trip through [df_to_ris()] is exact as long as `delimiter` does
#' not occur in the data, which is why [ris_sep()] is the default. A custom
#' delimiter that appears inside a real value will not split back correctly.
#'
#' @examples
#' recs <- structure(
#'   list(ref_1 = list(
#'     TY = "JOUR",
#'     TI = "A study",
#'     AU = c("Smith, J.", "Jones, A.")
#'   )),
#'   class = "ris_records"
#' )
#' ris_to_df(recs)
#'
#' @seealso [df_to_ris()] for the inverse.
#'
#' @export
ris_to_df <- function(x, delimiter = ris_sep()) {
  # columns appear in the order fields are first seen across x. Field names are
  # not reordered by length: an earlier version pushed names under 3 characters
  # to the end, to keep raw tags behind the semantic names the old reader
  # produced, but that also reordered any record whose field names were 3 or
  # more characters -- list(TY, ABCD, T1) came back as ABCD, TY, T1.
  cols <- unique(unlist(lapply(x, names)))

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

  # unname() before rbind(): rbind() otherwise takes row names from the names of
  # x_list and tries to translate them to the native encoding, warning once per
  # record for a name like "Goncalves_2024_ES&P". The record names are carried
  # by x itself, so nothing is lost by dropping them here.
  x_dframe <- data.frame(
    do.call(rbind, unname(x_list)),
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
#' @param x A data frame with one row per record. A `label` column, if you have
#'   added one, supplies the names of the result and is not treated as a field.
#' @param delimiter The string on which to split multi-value fields. Defaults
#'   to [ris_sep()]. Split with `fixed = TRUE`, so this is a literal string
#'   rather than a regular expression.
#'
#' @return A `ris_records` object: a named list with one element per record,
#'   each a named list of fields.
#'
#' @details
#' *Every* field is split, not just the ones that usually hold several values.
#' This is safe because the default delimiter cannot occur in bibliographic
#' text, so a value containing it can only have been joined by [ris_to_df()],
#' and no field needs special handling.
#'
#' Columns for which a record has no value are dropped rather than kept as
#' `NA`, so `is.null(x[[i]]$AB)` means what it says.
#'
#' [read_ris()] does not produce a `label` column, so records are normally named
#' `ref_1`, `ref_2`, … via [ris_index()]. Adding a `label` column yourself is
#' the way to name them something else.
#'
#' @examples
#' df <- data.frame(
#'   TY = "JOUR",
#'   TI = "A study",
#'   AU = "Smith, J. | Jones, A.",
#'   stringsAsFactors = FALSE
#' )
#' recs <- df_to_ris(df)
#' recs$ref_1$AU
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

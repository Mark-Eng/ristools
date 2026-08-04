# ============================================================================
#  Shared definitions
# ============================================================================

#' The multi-value field delimiter
#'
#' The string used to join multiple values in a single field, and to split
#' them apart again.
#'
#' @details
#' Bibliographic records routinely hold several values in one field: authors,
#' keywords, JEL descriptors, ISSNs. Collapsing a record into one row of a
#' data frame means joining those values, and the join has to be reversible.
#'
#' `" and "` -- the conventional choice, and what revtools used -- is not
#' reversible, because it occurs inside real values: author strings
#' (`"Jones and Partners, Mary B."`), journal titles (`"Journal of Economics
#' and Statistics"`), and EconLit descriptors such as `"Climate; Natural
#' Disasters and Their Management; Global Warming [Q54]"`. Splitting on it
#' corrupts those values, and no amount of lookahead fixes the general case.
#'
#' `" | "` cannot occur in bibliographic text, so *every* field can be split
#' on it unconditionally and no field needs special handling. This is what
#' makes the data frame to record conversion lossless.
#'
#' Always use this with `fixed = TRUE` in [strsplit()], [grepl()] and friends:
#' `|` is a regex metacharacter, and a pattern of `" | "` without `fixed`
#' matches something else entirely.
#'
#' @return A length-1 character vector, `" | "`.
#'
#' @examples
#' ris_sep()
#'
#' # correct
#' strsplit("Smith, J. | Jones, A.", ris_sep(), fixed = TRUE)[[1]]
#'
#' @export
ris_sep <- function() {
  " | "
}


#' Generate sequential record labels
#'
#' Builds zero-padded index labels for records that cannot be given a
#' meaningful name from their author and year.
#'
#' @param string Prefix for each label. Defaults to `"V"`.
#' @param n Number of labels to generate. If a vector is supplied, its length
#'   is used.
#' @param sep Separator between prefix and number. Defaults to `"_"`.
#'
#' @return A character vector of `n` labels.
#'
#' @examples
#' ris_index("ref", 3)
#' ris_index("ref", 12)
#'
#' @export
ris_index <- function(string, n, sep = "_") {
  if (missing(string)) {
    string <- "V"
  }
  if (missing(n)) {
    stop("n is missing from ris_index with no default")
  }
  if (n < 1) {
    stop("n must be > 0 for ris_index to function")
  }
  if (length(n) > 1) {
    n <- length(n)
  }
  size <- log10(n) + 1
  paste(
    string,
    formatC(seq_len(n), width = size, format = "d", flag = 0),
    sep = sep
  )
}

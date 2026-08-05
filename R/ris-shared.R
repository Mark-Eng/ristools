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
#' keywords, JEL descriptors, ISSNs. [ris_to_df()] joins those values with this
#' string when collapsing a record into one row, and [df_to_ris()] splits them
#' apart again.
#'
#' `" | "` is used because it does not occur in bibliographic text, so *every*
#' field can be split on it unconditionally, no field needs special handling,
#' and the round trip is exact. The conventional `" and "` is not safe: it
#' appears inside real author names (`"Jones and Partners, Mary B."`), journal
#' titles (`"Journal of Economics and Statistics"`), and descriptors such as
#' `"Climate; Natural Disasters and Their Management; Global Warming [Q54]"`,
#' all of which splitting would corrupt.
#'
#' `|` is a regex metacharacter, so always pass `fixed = TRUE` when using this
#' string as a pattern in [strsplit()], [grepl()] and friends. Without it the
#' pattern matches something else entirely.
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
#' Builds numbered labels such as `ref_01`, `ref_02`. Used to name records
#' where no author/year label can be built, and available for labelling records
#' yourself.
#'
#' @param string Prefix for each label. Defaults to `"V"`.
#' @param n Number of labels to generate. If a vector is supplied, its length
#'   is used.
#' @param sep Separator between prefix and number. Defaults to `"_"`.
#'
#' @return A character vector of `n` labels, zero-padded to a common width so
#'   they sort in order.
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

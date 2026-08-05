# ============================================================================
#  Splitting a large RIS file into smaller ones
# ============================================================================

#' Split a RIS file into fixed-size chunks
#'
#' Splits a large RIS export into several smaller files, each holding at most
#' `set_size` records. Useful where a downstream tool caps the number of
#' records it will accept per import.
#'
#' @param input_file Path to the RIS file to split.
#' @param output_dir Directory to write the chunks to. Created if it does not
#'   exist.
#' @param set_size Maximum number of records -- not lines -- per output file.
#'   Defaults to 10000.
#'
#' @return A character vector of the paths written, invisibly.
#'
#' @details
#' Works at the text level: records are delimited by lines starting `TY  - `
#' and `ER  -`, and the lines between them are copied verbatim. Nothing is
#' parsed, so no field can be altered or lost in the process.
#'
#' Output files are named after the input, with the record range appended --
#' `"export (1-10,000).ris"`, `"export (10,001-20,000).ris"` and so on. Any
#' existing parenthesised suffix on the input name is dropped first, so
#' re-splitting an already-split file does not accumulate suffixes.
#'
#' @examples
#' # build a small RIS file with 5 records
#' f <- tempfile(fileext = ".ris")
#' writeLines(
#'   unlist(lapply(1:5, function(i) {
#'     c("TY  - JOUR", paste0("T1  - Record ", i), "ER  - ")
#'   })),
#'   f
#' )
#'
#' out <- file.path(tempdir(), "chunks")
#' split_ris_file(f, out, set_size = 2)
#' basename(list.files(out))
#'
#' unlink(f)
#' unlink(out, recursive = TRUE)
#'
#' @export
split_ris_file <- function(input_file, output_dir, set_size = 10000) {
  if (!file.exists(input_file)) {
    stop("input file not found: ", input_file)
  }
  if (set_size < 1) {
    stop("set_size must be >= 1")
  }

  ris_lines <- readLines(input_file, warn = FALSE)

  # identify start and end of each record
  id_ty <- grep("^TY  - ", ris_lines)
  id_er <- grep("^ER  -", ris_lines)

  if (length(id_ty) == 0) {
    stop("no 'TY  - ' lines found: is this a RIS file?")
  }
  if (length(id_ty) != length(id_er)) {
    stop(
      "number of 'TY -' and 'ER -' lines do not match (",
      length(id_ty), " vs ", length(id_er),
      "). Please check the input file."
    )
  }

  # extract input file name, dropping any existing "(n-m)" suffix
  file_base <- basename(input_file)
  file_base <- sub("\\.ris$", "", file_base, ignore.case = TRUE)
  file_base <- sub("\\s*\\([^)]*\\)\\s*$", "", file_base)

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # split records into sets of the requested size
  n_refs <- length(id_ty)
  set_id <- (seq_len(n_refs) - 1) %/% set_size
  sets <- split(seq_len(n_refs), set_id)

  written <- vapply(
    sets,
    function(refs) {
      start_ref <- min(refs)
      end_ref <- max(refs)
      lines_to_write <- ris_lines[id_ty[start_ref]:id_er[end_ref]]

      # thousands separators in the file name, to match the input convention
      start_label <- formatC(start_ref, format = "d", big.mark = ",")
      end_label <- formatC(end_ref, format = "d", big.mark = ",")

      file_name <- sprintf("%s (%s-%s).ris", file_base, start_label, end_label)
      file_path <- file.path(output_dir, file_name)

      writeLines(lines_to_write, file_path)
      message("Wrote ", file_name)
      file_path
    },
    character(1)
  )

  invisible(unname(written))
}

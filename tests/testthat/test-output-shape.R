# Tests for the shape of read_ris()'s output: one column per RIS tag in the
# input and nothing else, no label column, row names that just number the rows,
# and a filename column that records provenance on a multi-file read.

test_that("the data frame has one column per tag in the file and no label", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  # every tag in the file becomes a column, except ER, which terminates a
  # record rather than carrying a value
  tags <- unique(sub("  - .*$", "", grep("^[A-Z][A-Z0-9]  - ", awkward_ris(), value = TRUE)))
  tags <- setdiff(tags, "ER")

  expect_false("label" %in% colnames(df))
  expect_setequal(colnames(df), tags)
  expect_equal(ncol(df), length(tags))
})

test_that("ris_to_df adds no label column of its own", {
  recs <- structure(
    list(ref_1 = list(TY = "JOUR", TI = "A study", AU = c("Smith, J.", "Jones, A."))),
    class = "ris_records"
  )

  df <- ris_to_df(recs)

  expect_equal(colnames(df), c("TY", "TI", "AU"))
  expect_false("label" %in% colnames(df))
})

test_that("column order follows first appearance, whatever the name length", {
  # an earlier version pushed names under 3 characters to the end, which
  # reordered any record whose fields were named with 3 or more characters
  recs <- structure(
    list(ref_1 = list(TY = "JOUR", ABCD = "long name", T1 = "A study")),
    class = "ris_records"
  )

  expect_equal(colnames(ris_to_df(recs)), c("TY", "ABCD", "T1"))
})

test_that("a single-file read numbers its rows", {
  f <- write_temp_ris(c(awkward_ris(), sparse_ris()))
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(nrow(df), 2)
  expect_equal(rownames(df), c("1", "2"))
})

test_that("records in the list form are named by position", {
  f <- write_temp_ris(c(awkward_ris(), sparse_ris()))
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_equal(names(recs), c("ref_1", "ref_2"))
})

test_that("a multi-file read records the bare file name by default", {
  f1 <- write_temp_ris(awkward_ris())
  f2 <- write_temp_ris(sparse_ris())
  on.exit(unlink(c(f1, f2)))

  df <- read_ris(c(f1, f2))

  expect_equal(sort(unique(df$filename)), sort(basename(c(f1, f2))))
  expect_false(any(grepl(.Platform$file.sep, df$filename, fixed = TRUE)))
})

test_that("full_path = TRUE records the path as passed", {
  f1 <- write_temp_ris(awkward_ris())
  f2 <- write_temp_ris(sparse_ris())
  on.exit(unlink(c(f1, f2)))

  df <- read_ris(c(f1, f2), full_path = TRUE)

  expect_equal(sort(unique(df$filename)), sort(c(f1, f2)))
})

test_that("a multi-file read numbers its rows rather than naming them by path", {
  f1 <- write_temp_ris(awkward_ris())
  f2 <- write_temp_ris(sparse_ris())
  on.exit(unlink(c(f1, f2)))

  df <- read_ris(c(f1, f2))

  expect_equal(rownames(df), c("1", "2"))
  expect_false(any(grepl("\\.ris", rownames(df))))
})

test_that("the same file name in two directories warns but is not mangled", {
  d1 <- file.path(tempdir(), paste0("dir1_", basename(tempfile())))
  d2 <- file.path(tempdir(), paste0("dir2_", basename(tempfile())))
  dir.create(d1)
  dir.create(d2)
  on.exit(unlink(c(d1, d2), recursive = TRUE))

  f1 <- file.path(d1, "export.ris")
  f2 <- file.path(d2, "export.ris")
  writeLines(awkward_ris(), f1)
  writeLines(sparse_ris(), f2)

  expect_warning(df <- read_ris(c(f1, f2)), "more than one directory")

  # the column keeps the true name for both records rather than being
  # de-duplicated to export.ris.1, which would misreport the source
  expect_equal(df$filename, c("export.ris", "export.ris"))

  expect_no_warning(read_ris(c(f1, f2), full_path = TRUE))
})

test_that("full_path does not affect a single-file read", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  expect_equal(read_ris(f), read_ris(f, full_path = TRUE))
})

test_that("a file with no ER terminator is rejected, not guessed at", {
  f <- write_temp_ris(c("TY  - JOUR", "T1  - No terminator", "A1  - Smith, J", ""))
  on.exit(unlink(f))

  expect_error(read_ris(f), "no 'ER' record terminator")
})

test_that("blank-line delimited records are rejected", {
  # revtools treated a blank line as a record separator. That fallback was
  # untested and is gone; such a file must now say so rather than misparse.
  f <- write_temp_ris(c(
    "TY  - JOUR", "T1  - First", "",
    "TY  - JOUR", "T1  - Second", ""
  ))
  on.exit(unlink(f))

  expect_error(read_ris(f), "no 'ER' record terminator")
})

test_that("a Web of Science .ciw file is rejected with a usable message", {
  # .ciw carries an ER line, so it gets past the terminator guard and has to be
  # caught on its tags: they are a bare two characters and a single space
  f <- write_temp_ris(wos_ciw(), ext = ".ciw")
  on.exit(unlink(f))

  expect_error(read_ris(f), "no RIS tags found")
})

test_that("a PubMed .nbib file is rejected with a usable message", {
  f <- write_temp_ris(pubmed_nbib(), ext = ".nbib")
  on.exit(unlink(f))

  expect_error(read_ris(f), "is this a RIS file")
})

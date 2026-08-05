test_that("a RIS file survives read -> write -> read unchanged", {
  f1 <- write_temp_ris(c(awkward_ris(), sparse_ris()))
  on.exit(unlink(f1), add = TRUE)

  df1 <- read_ris(f1)

  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(f2), add = TRUE)
  write_ris(df1, f2)

  df2 <- read_ris(f2)

  # every field present in both must be identical
  common <- intersect(colnames(df1), colnames(df2))
  expect_gt(length(common), 10)
  for (cl in common) {
    expect_equal(df1[[cl]], df2[[cl]], info = paste("field:", cl))
  }
})

test_that("an author containing ' and ' is not split", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_length(recs[[1]]$A1, 2)
  expect_equal(recs[[1]]$A1[2], "Jones and Partners, Mary B.")
})

test_that("EconLit descriptors containing ' and ' survive intact", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_length(recs[[1]]$M3, 2)
  expect_equal(
    recs[[1]]$M3[1],
    "Climate; Natural Disasters and Their Management; Global Warming [Q54]"
  )
})

test_that("an abbreviated end page keeps its tag and its order", {
  f1 <- write_temp_ris(awkward_ris())
  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(c(f1, f2)))

  df <- read_ris(f1)

  # SP 419 / EP 41: an end page lower than the start page is what a sort()
  # would have reversed, so the tags must carry the distinction
  expect_equal(df$SP[1], "419")
  expect_equal(df$EP[1], "41")

  # and the written file keeps the start page ahead of the end page
  write_ris(df, f2)
  written <- readLines(f2)
  expect_lt(grep("^SP  - 419", written)[1], grep("^EP  - 41", written)[1])
})

test_that("a bare year is written back bare, not given an Ovid suffix", {
  # write_ris() used to append "//" to a 4-digit year, on the assumption that
  # the reader would strip it again. The reader preserves values as written, so
  # the suffix accumulated: 2024 -> 2024// -> 2024////
  f1 <- write_temp_ris(c(
    "TY  - JOUR",
    "TI  - A study",
    "AU  - Smith, J",
    "PY  - 2024",
    "ER  - ",
    ""
  ))
  f2 <- tempfile(fileext = ".ris")
  f3 <- tempfile(fileext = ".ris")
  on.exit(unlink(c(f1, f2, f3)))

  d1 <- read_ris(f1)
  expect_equal(d1$PY, "2024")

  write_ris(d1, f2)
  d2 <- read_ris(f2)
  expect_equal(d2$PY, "2024")

  # and a second trip does not compound it
  write_ris(d2, f3)
  expect_equal(read_ris(f3)$PY, "2024")

  # the Ovid form is still available on request
  f4 <- tempfile(fileext = ".ris")
  on.exit(unlink(f4), add = TRUE)
  write_ris(d1, f4, year_suffix = "//")
  expect_equal(read_ris(f4)$PY, "2024//")
})

test_that("a year already carrying a suffix is left alone", {
  f1 <- write_temp_ris(awkward_ris())
  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(c(f1, f2)))

  d1 <- read_ris(f1)
  expect_equal(d1$Y1, "2020//")

  write_ris(d1, f2)
  expect_equal(read_ris(f2)$Y1, "2020//")
})

test_that("a trailing full stop in a title is kept", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(df$T1[1], "Adaptation in the U.S.")
})

test_that("tags containing a digit keep their case", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_true("M3" %in% colnames(df))
  expect_false("m3" %in% colnames(df))
})

test_that("multiple files are combined with a filename column", {
  f1 <- write_temp_ris(awkward_ris())
  f2 <- write_temp_ris(sparse_ris())
  on.exit(unlink(c(f1, f2)))

  df <- read_ris(c(f1, f2))

  expect_equal(nrow(df), 2)
  expect_true("filename" %in% colnames(df))
  expect_equal(sort(unique(df$filename)), sort(basename(c(f1, f2))))

  # the row names should number the rows, not carry the source path over from
  # the per-file frames rbind() was given
  expect_equal(rownames(df), as.character(seq_len(nrow(df))))
})
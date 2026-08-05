test_that("a BibTeX file survives read -> write -> read", {
  f1 <- write_temp_ris(c(awkward_ris(), sparse_ris()))
  fb <- tempfile(fileext = ".bib")
  on.exit(unlink(c(f1, fb)))

  df1 <- read_ris(f1, rename_columns = TRUE)
  write_ris(df1, fb, format = "bib")
  df2 <- read_ris(fb)

  expect_equal(nrow(df2), nrow(df1))
  for (cl in c("title", "author", "year", "journal")) {
    expect_equal(df2[[cl]], df1[[cl]], info = paste("field:", cl))
  }
})

test_that("multi-value fields in .bib use the shared delimiter", {
  # revtools joined authors with " and " and other fields with "; ", and its
  # reader never split on "; ", so those values could not be read back
  df <- data.frame(
    label = "ref_1",
    type = "JOUR",
    title = "A study",
    author = paste("Smith, J.", "Jones, A.", sep = ris_sep()),
    keywords = paste("climate", "growth", sep = ris_sep()),
    stringsAsFactors = FALSE
  )

  fb <- tempfile(fileext = ".bib")
  on.exit(unlink(fb))
  write_ris(df, fb, format = "bib")

  written <- readLines(fb)
  expect_true(any(grepl("author={Smith, J. | Jones, A.},", written, fixed = TRUE)))
  expect_true(any(grepl("keywords={climate | growth},", written, fixed = TRUE)))

  back <- read_ris(fb, return_df = FALSE)
  expect_equal(back[[1]]$author, c("Smith, J.", "Jones, A."))
  expect_equal(back[[1]]$keywords, c("climate", "growth"))
})

test_that("bib output is written with LF line endings by default", {
  df <- data.frame(
    label = "ref_1", type = "JOUR", title = "A study",
    stringsAsFactors = FALSE
  )
  fb <- tempfile(fileext = ".bib")
  on.exit(unlink(fb))

  write_ris(df, fb, format = "bib")

  raw_bytes <- readBin(fb, "raw", file.size(fb))
  expect_false(any(raw_bytes == as.raw(13))) # no CR
})

test_that("ris output is written with CRLF line endings by default", {
  df <- data.frame(
    label = "ref_1", type = "JOUR", title = "A study",
    stringsAsFactors = FALSE
  )
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  write_ris(df, f)

  raw_bytes <- readBin(f, "raw", file.size(f))
  expect_true(any(raw_bytes == as.raw(13))) # CR present
})

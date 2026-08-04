test_that("a RIS file survives read -> write -> read unchanged", {
  f1 <- write_temp_ris(c(awkward_ris(), sparse_ris()))
  on.exit(unlink(f1), add = TRUE)

  df1 <- read_ris(f1)

  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(f2), add = TRUE)
  write_ris(df1, f2)

  df2 <- read_ris(f2)

  # every field present in both must be identical; label is regenerated from
  # author/year/journal so it is compared separately
  common <- setdiff(intersect(colnames(df1), colnames(df2)), "label")
  expect_gt(length(common), 10)
  for (cl in common) {
    expect_equal(df1[[cl]], df2[[cl]], info = paste("field:", cl))
  }
})

test_that("an author containing ' and ' is not split", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_length(recs[[1]]$author, 2)
  expect_equal(recs[[1]]$author[2], "Jones and Partners, Mary B.")
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

test_that("an abbreviated end page is not reordered", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  # sort() would have produced "41-419"
  expect_equal(df$pages[1], "419-41")
})

test_that("a trailing full stop in a title is kept", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(df$title[1], "Adaptation in the U.S.")
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
  expect_equal(sort(unique(df$filename)), sort(c(f1, f2)))
})
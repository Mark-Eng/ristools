# Regression tests for the RIS tag pattern.
#
# EBSCO Discovery breaks a multi-value KW field across several lines without
# repeating the tag. The original pattern made the "  - " separator optional,
# so a keyword whose first word looked like a tag was parsed as one. The read
# never failed, which is what made this expensive: keywords were silently
# truncated, misfiled or deleted. Fixed by requiring the separator.

test_that("a wrapped keyword field keeps every keyword, in order", {
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_equal(recs[[1]]$KW, wrapped_kw_expected())
})

test_that("a keyword whose first word looks like a tag is not truncated", {
  # "E7 economies" matched as tag "E7" with text "economies", so the keyword
  # lost its first word
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_true("E7 economies" %in% recs[[1]]$KW)
  expect_false("economies" %in% recs[[1]]$KW)
})

test_that("a keyword that is entirely tag-like is not dropped", {
  # "EKC" and "GHG" matched in full, leaving no text, and were then removed by
  # the empty-row filter in prep_ris()
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_true(all(c("EKC", "GHG") %in% recs[[1]]$KW))
})

test_that("a JEL code keyword is not split into a tag and a digit", {
  # "F34" matched as tag "F3" with text "4"; likewise "Q54" as "Q5" + "4"
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_true(all(c("F34", "Q54") %in% recs[[1]]$KW))
  expect_false("4" %in% recs[[1]]$KW)
})

test_that("a wrapped keyword field creates no spurious fields", {
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_false(any(c("E7", "EKC", "GHG", "F3", "Q5") %in% names(recs[[1]])))
})

test_that("a wrapped abstract keeps a tag-like continuation line", {
  # "CO2 emissions are discussed" was torn out of the abstract into a CO2 field
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  # the continuation line stays under AB, as its own value: the reader does not
  # join wrapped lines, so that nothing is invented about how they relate
  expect_equal(
    recs[[1]]$AB,
    c(
      "An abstract that wraps mid-field.",
      "CO2 emissions are discussed at length."
    )
  )
  expect_false("CO2" %in% names(recs[[1]]))
})

test_that("wrapped fields survive the data frame conversion", {
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(
    df$KW,
    paste(wrapped_kw_expected(), collapse = ris_sep())
  )
  expect_false(any(c("E7", "EKC", "GHG", "F3", "Q5", "CO2") %in% colnames(df)))
})

test_that("wrapped keywords round-trip through write_ris", {
  f1 <- write_temp_ris(wrapped_kw_ris())
  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(c(f1, f2)))

  df1 <- read_ris(f1)
  write_ris(df1, f2)
  df2 <- read_ris(f2)

  expect_equal(df2$KW, df1$KW)
})

test_that("a well-formed file parses exactly as before", {
  # the stricter pattern must be a no-op on input that repeats its tags
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_equal(
    recs[[1]]$A1,
    c("Smith, John A.", "Jones and Partners, Mary B.")
  )
  expect_equal(recs[[1]]$T1, "Adaptation in the U.S.")
  # SP and EP stay as they were written, each under its own tag
  expect_equal(recs[[1]]$SP, "419")
  expect_equal(recs[[1]]$EP, "41")
  expect_equal(recs[[1]]$SN, c("0022-1821", "1467-6451"))
})

test_that("a tag containing a digit still matches", {
  f <- write_temp_ris(c(
    "TY  - JOUR",
    "T1  - Digit-bearing tags",
    "A1  - Green, Sam",
    "Y1  - n.d.",
    "U1  - 12345",
    "M3  - Article",
    "ER  - ",
    ""
  ))
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  # a year value carrying no 4-digit year is kept as it was written
  expect_equal(recs[[1]]$Y1, "n.d.")
  expect_equal(recs[[1]]$U1, "12345")
  expect_equal(recs[[1]]$M3, "Article")
})

test_that("a bare 'ER  -' with no trailing space ends a record", {
  # write_ris() emits "ER  -" without a trailing space, so a pattern that
  # required one would break every file this package writes
  f <- write_temp_ris(c(
    "TY  - JOUR",
    "T1  - First record",
    "A1  - Grey, Robin",
    "Y1  - 2021//",
    "ER  -",
    "TY  - JOUR",
    "T1  - Second record",
    "A1  - Blue, Alex",
    "Y1  - 2022//",
    "ER  -",
    ""
  ))
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(nrow(df), 2)
  expect_equal(df$T1, c("First record", "Second record"))
})

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

  expect_equal(recs[[1]]$keywords, wrapped_kw_expected())
})

test_that("a keyword whose first word looks like a tag is not truncated", {
  # "E7 economies" matched as tag "E7" with text "economies", so the keyword
  # lost its first word
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_true("E7 economies" %in% recs[[1]]$keywords)
  expect_false("economies" %in% recs[[1]]$keywords)
})

test_that("a keyword that is entirely tag-like is not dropped", {
  # "EKC" and "GHG" matched in full, leaving no text, and were then removed by
  # the empty-row filter in prep_ris()
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_true(all(c("EKC", "GHG") %in% recs[[1]]$keywords))
})

test_that("a JEL code keyword is not split into a tag and a digit", {
  # "F34" matched as tag "F3" with text "4"; likewise "Q54" as "Q5" + "4"
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_true(all(c("F34", "Q54") %in% recs[[1]]$keywords))
  expect_false("4" %in% recs[[1]]$keywords)
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

  expect_equal(
    recs[[1]]$abstract,
    "An abstract that wraps mid-field. CO2 emissions are discussed at length."
  )
  expect_false("CO2" %in% names(recs[[1]]))
})

test_that("wrapped fields survive the data frame conversion", {
  f <- write_temp_ris(wrapped_kw_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(
    df$keywords,
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

  expect_equal(df2$keywords, df1$keywords)
})

test_that("a well-formed file parses exactly as before", {
  # the stricter pattern must be a no-op on input that repeats its tags
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_equal(
    recs[[1]]$author,
    c("Smith, John A.", "Jones and Partners, Mary B.")
  )
  expect_equal(recs[[1]]$title, "Adaptation in the U.S.")
  expect_equal(recs[[1]]$pages, "419-41")
  expect_equal(recs[[1]]$issn, c("0022-1821", "1467-6451"))
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

  expect_equal(recs[[1]]$year, "n.d.")
  expect_equal(recs[[1]]$eppi_id, "12345")
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
  expect_equal(df$title, c("First record", "Second record"))
})

test_that("a Web of Science .ciw file still parses", {
  # .ciw tags are a bare two characters and a single space, with no hyphen, so
  # they keep the original permissive pattern via tag_type
  f <- write_temp_ris(wos_ciw(), ext = ".ciw")
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(nrow(df), 1)
  expect_equal(df$title, "A record in Web of Science format")
  expect_equal(df$year, "2018")
  expect_equal(df$author, paste("Smith, J", "Jones, M", sep = ris_sep()))
})

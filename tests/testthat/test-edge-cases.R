test_that("a field absent from the file gains no column", {
  # revtools tested length(result$abstract > 1), which is always 1, so every
  # record without an abstract had an empty one added
  f <- write_temp_ris(sparse_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)
  expect_null(recs[[1]]$N2)
  expect_null(recs[[1]]$AB)

  df <- read_ris(f)
  expect_false(any(c("N2", "AB") %in% colnames(df)))
})

test_that("an end page with no start page keeps its own tag", {
  f1 <- write_temp_ris(sparse_ris())
  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(c(f1, f2)))

  df1 <- read_ris(f1)

  # the tag itself distinguishes an end page from a start page, so no
  # leading-dash convention is needed to tell "218" from a start page of 218
  expect_equal(df1$EP, "218")
  expect_false("SP" %in% colnames(df1))

  write_ris(df1, f2)
  expect_true(any(grepl("^EP  - 218", readLines(f2))))

  df2 <- read_ris(f2)
  expect_equal(df2$EP, "218")
  expect_false("SP" %in% colnames(df2))
})

test_that("a year value with no 4-digit year is kept rather than blanked", {
  f <- write_temp_ris(c(
    "TY  - JOUR",
    "T1  - Undated work",
    "A1  - Green, Sam",
    "Y1  - n.d.",
    "ER  - ",
    ""
  ))
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_equal(recs[[1]]$Y1, "n.d.")
})

test_that("a lone start page survives a round trip", {
  f <- write_temp_ris(c(
    "TY  - JOUR",
    "T1  - One page only",
    "A1  - Grey, Robin",
    "Y1  - 2021//",
    "SP  - 77",
    "ER  - ",
    ""
  ))
  on.exit(unlink(f))

  df <- read_ris(f)
  expect_equal(df$SP, "77")
  expect_false("EP" %in% colnames(df))

  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(f2), add = TRUE)
  write_ris(df, f2)
  expect_true(any(grepl("^SP  - 77", readLines(f2))))
})

test_that("two tags that describe the same thing stay separate", {
  f <- write_temp_ris(c(
    "TY  - JOUR",
    "T1  - A chapter",
    "A1  - Black, Kim",
    "Y1  - 2018//",
    "JF  - Journal of Things",
    "T3  - A Series Title",
    "ER  - ",
    ""
  ))
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  # neither value is folded into the other, and neither loses its tag
  expect_equal(recs[[1]]$JF, "Journal of Things")
  expect_equal(recs[[1]]$T3, "A Series Title")
})

test_that("a TY with no ER is reported with its line number", {
  f <- write_temp_ris(missing_er_ris())
  on.exit(unlink(f))

  # line numbers are the file's own, despite the tab on line 2
  err <- expect_error(read_ris(f), "found 3 'TY' lines .* but 2 'ER' lines")
  expect_match(
    conditionMessage(err),
    "line 5: 'TY' has no 'ER' before the next 'TY' (line 8)",
    fixed = TRUE
  )
  expect_match(conditionMessage(err), basename(f), fixed = TRUE)
})

test_that("an ER with no TY and a TY at end of file are both reported", {
  f <- write_temp_ris(c(
    tiny_ris_record("One"),        # lines 1-4
    "ER  - ",                      # line 5: stray
    "",
    tiny_ris_record("Two"),        # lines 7-10
    "TY  - JOUR",                  # line 11: never closed
    "T1  - Last"
  ))
  on.exit(unlink(f))

  # equal counts (3 TY, 3 ER) but they don't pair up: previously this built a
  # reversed line range and returned garbage rather than failing
  err <- expect_error(read_ris(f), "do not pair up")
  msg <- conditionMessage(err)
  expect_match(msg, "line  5: 'ER' has no 'TY' opening its record", fixed = TRUE)
  expect_match(
    msg, "line 11: 'TY' has no 'ER' before the end of the file", fixed = TRUE
  )
})

test_that("only the first 10 unmatched lines are listed", {
  # 15 records, each missing its ER
  lines <- unlist(lapply(seq_len(15), function(i) {
    c("TY  - JOUR", paste0("T1  - Rec ", i), "")
  }))
  f <- write_temp_ris(c(lines, "ER  - ", ""))
  on.exit(unlink(f))

  err <- expect_error(read_ris(f), "first 10 of 14")
  listed <- regmatches(
    conditionMessage(err),
    gregexpr("line +[0-9]+:", conditionMessage(err))
  )[[1]]
  expect_length(listed, 10)
})

test_that("a missing file raises an error", {
  expect_error(read_ris(tempfile(fileext = ".ris")), "file not found")
})

test_that("write_ris rejects an unsupported object", {
  expect_error(write_ris(1:10, tempfile()), "only accepts objects")
})

test_that("write_ris requires a filename", {
  df <- data.frame(label = "ref_1", title = "x", stringsAsFactors = FALSE)
  expect_error(write_ris(df), "filename")
})

test_that("ris_index pads to a consistent width", {
  expect_equal(ris_index("ref", 3), c("ref_1", "ref_2", "ref_3"))
  expect_equal(ris_index("ref", 10)[1], "ref_01")
  expect_error(ris_index("ref", 0), "must be > 0")
})

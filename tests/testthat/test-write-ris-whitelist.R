# ============================================================================
#  write_ris()'s tag whitelist
#
#  A column reaches the file if tag_map names it, or the dialect maps it, or it
#  is already one of ris_valid_tags(). Everything else is dropped with one
#  warning. Before 0.4.0 the last check was the shape pattern
#  "^[A-Z][A-Z0-9]{1,3}$", which let any two-to-four character uppercase token
#  through -- including ER, which split every record it appeared in.
# ============================================================================

test_that("the whitelist covers every tag the writer can emit", {
  # not derived from ris_write_tags(), so this has something to catch: a
  # mapping added to a tag that is not a real one fails here
  for (d in c("ovid", "generic")) {
    tags <- ristools:::ris_write_tags(d)
    expect_true(
      all(tags$map$ris %in% ris_valid_tags()),
      info = paste("dialect:", d)
    )
    expect_true(
      all(tags$order %in% ris_valid_tags()),
      info = paste("order, dialect:", d)
    )
  }
})

test_that("ER is not writable as a field", {
  # it terminates a record; writing it as data splits the record in two
  expect_false("ER" %in% ris_valid_tags())

  df <- data.frame(TY = "JOUR", TI = "A study", ER = "junk")
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_warning(write_ris(df, f), "ER")
  expect_equal(sum(readLines(f, warn = FALSE) == "ER  -"), 1)
  expect_equal(nrow(read_ris(f)), 1)
})

test_that("a tag-shaped but invalid name is dropped, not written", {
  df <- data.frame(
    TY = "JOUR",
    TI = "A study",
    TITL = "not a tag",
    SDG1 = "not a tag either",
    stringsAsFactors = FALSE
  )
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_warning(write_ris(df, f), "TITL\n  SDG1")
  lines <- readLines(f, warn = FALSE)
  expect_false(any(grepl("^TITL", lines)))
  expect_false(any(grepl("^SDG1", lines)))
})

test_that("the warning names every dropped column, in one message", {
  df <- data.frame(
    TY = "JOUR",
    alpha = 1,
    beta = 2,
    stringsAsFactors = FALSE
  )
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_warning(
    write_ris(df, f),
    paste0(
      "The following columns are not named with valid RIS tags; they have ",
      "been excluded from your RIS file:\n  alpha\n  beta"
    ),
    fixed = TRUE
  )
})

test_that("warn_dropped = FALSE drops the columns without saying so", {
  df <- data.frame(
    TY = "JOUR",
    TI = "A study",
    alpha = 1,
    stringsAsFactors = FALSE
  )
  df$nested <- list(list(a = 1))
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_no_warning(write_ris(df, f, warn_dropped = FALSE))

  # silence is not permission: the columns are still dropped, so the file is
  # the same one the warning would have described
  lines <- readLines(f, warn = FALSE)
  expect_false(any(grepl("alpha|nested|list\\(", lines)))
  expect_equal(read_ris(f)$TI, "A study")

  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(f2), add = TRUE)
  suppressWarnings(write_ris(df, f2))
  expect_identical(readLines(f, warn = FALSE), readLines(f2, warn = FALSE))
})

test_that("dropped columns are listed one per line", {
  df <- data.frame(TY = "JOUR", alpha = 1, beta = 2, gamma = 3)
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  msg <- tryCatch(write_ris(df, f), warning = conditionMessage)

  # a comma-separated list ran together once it was more than a few names
  # long, which is the normal case for oa2df() output
  expect_match(msg, "RIS file:\n  alpha\n  beta\n  gamma", fixed = TRUE)
  expect_false(grepl("alpha, beta", msg, fixed = TRUE))
})

test_that("semantically named columns still write", {
  # the whitelist is applied after the field -> tag mapping, not before. A
  # bare-name check would drop these, breaking BibTeX reads and every
  # revtools-era data frame.
  df <- data.frame(
    type = "JOUR",
    title = "A study",
    author = "Smith, J. | Jones, A.",
    year = "2020",
    stringsAsFactors = FALSE
  )
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_no_warning(write_ris(df, f))
  lines <- readLines(f, warn = FALSE)
  expect_true("TY  - JOUR" %in% lines)
  expect_true("T1  - A study" %in% lines)
  expect_true("A1  - Smith, J." %in% lines)
  expect_true("Y1  - 2020" %in% lines)
})

test_that("tag_map is the escape hatch for a tag not on the whitelist", {
  df <- data.frame(TY = "JOUR", custom = "keep me", stringsAsFactors = FALSE)
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_no_warning(write_ris(df, f, tag_map = c(custom = "U4")))
  expect_true("U4  - keep me" %in% readLines(f, warn = FALSE))
})

test_that("a list column cannot be deparsed into the file", {
  # the drop happens before prepare_entries() coerces with as.character(),
  # which would otherwise write "list(a = 1, b = 2)" as a field value
  df <- data.frame(TY = "JOUR", TI = "A study", stringsAsFactors = FALSE)
  df$nested <- list(list(a = 1, b = "two"))
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_warning(write_ris(df, f), "nested")
  expect_false(any(grepl("list(", readLines(f, warn = FALSE), fixed = TRUE)))
})

test_that("a nested column is dropped even when its name is a valid tag", {
  # openalexR::oa2df() calls its nested tibble of keyword objects "keywords",
  # which maps to KW. The name check cannot catch that: the name is right and
  # the contents are not.
  df <- data.frame(TY = "JOUR", TI = "A study", stringsAsFactors = FALSE)
  df$keywords <- list(data.frame(display_name = c("alpha", "beta")))
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_warning(write_ris(df, f), "nested tables")
  lines <- readLines(f, warn = FALSE)
  expect_false(any(grepl("list(", lines, fixed = TRUE)))
  expect_false(any(grepl("^KW", lines)))
  expect_equal(nrow(read_ris(f)), 1)
})

test_that("a writable column is never dropped by accident", {
  f1 <- write_temp_ris(c(awkward_ris(), sparse_ris()))
  on.exit(unlink(f1), add = TRUE)
  df <- read_ris(f1)

  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(f2), add = TRUE)

  expect_no_warning(write_ris(df, f2))
  expect_equal(sort(colnames(read_ris(f2))), sort(colnames(df)))
})

test_that("BibTeX output is not filtered by the whitelist", {
  # a .bib file's field names are field names, not tags
  df <- data.frame(
    type = "JOUR",
    title = "A study",
    anything_at_all = "kept",
    stringsAsFactors = FALSE
  )
  f <- tempfile(fileext = ".bib")
  on.exit(unlink(f))

  expect_no_warning(write_ris(df, f, format = "bib"))
  expect_true(any(grepl("anything_at_all", readLines(f, warn = FALSE))))
})

test_that("label and filename are dropped silently", {
  df <- data.frame(
    label = "ref_1",
    filename = "export.ris",
    TY = "JOUR",
    TI = "A study",
    stringsAsFactors = FALSE
  )
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_no_warning(write_ris(df, f))
  expect_false(any(grepl("export.ris", readLines(f, warn = FALSE))))
})

test_that("a record list is filtered the same way as a data frame", {
  recs <- structure(
    list(ref_1 = list(TY = "JOUR", TI = "A study", nonsense = "drop me")),
    class = "ris_records"
  )
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  expect_warning(write_ris(recs, f), "nonsense")
  expect_false(any(grepl("drop me", readLines(f, warn = FALSE))))
})

test_that("the new tags have a place in the canonical order", {
  # without one they sort to the end of the record, after N1
  df <- data.frame(
    TY = "JOUR",
    N1 = "a note",
    U3 = "SDGs: Quality education",
    DA = "2017-11-01",
    PY = "2017",
    TI = "A study",
    stringsAsFactors = FALSE
  )
  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))

  write_ris(df, f)
  tags <- sub("  - .*$", "", readLines(f, warn = FALSE))

  expect_equal(tags[1], "TY")
  expect_lt(match("TI", tags), match("PY", tags))
  expect_lt(match("PY", tags), match("DA", tags))
  expect_lt(match("DA", tags), match("U3", tags))
  expect_lt(match("U3", tags), match("N1", tags))
})

test_that("ris_valid_tags is sorted, unique and tag-shaped", {
  tags <- ris_valid_tags()

  expect_type(tags, "character")
  expect_equal(tags, sort(unique(tags)))
  expect_true(all(grepl("^[A-Z][A-Z0-9]$", tags)))
  # read_ris() only ever produces two-character names, so anything longer
  # could not have come from a file this package read
  expect_true(all(nchar(tags) == 2))
})

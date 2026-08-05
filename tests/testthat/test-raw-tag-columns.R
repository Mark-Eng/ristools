# Tests for read_ris()'s default output shape: one column per raw RIS tag,
# with no renaming or merging, so a file can be read, inspected as a table,
# and written back out with nothing lost or relabelled along the way.
# rename_columns = TRUE restores the semantic naming this package used by
# default before 0.2.0.

test_that("the default read names columns after raw tags, not semantic fields", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_true(all(c("T1", "A1", "Y1", "JF", "SP", "EP", "M3", "SN", "DO") %in% colnames(df)))
  expect_false(any(c("title", "author", "year", "journal", "pages") %in% colnames(df)))
})

test_that("column names follow the source file's own tags, not a fixed schema", {
  f_ovid <- write_temp_ris(awkward_ris())
  f_econlit <- write_temp_ris(econlit_ris())
  on.exit(unlink(c(f_ovid, f_econlit)))

  df_ovid <- read_ris(f_ovid)
  df_econlit <- read_ris(f_econlit)

  expect_true(all(c("T1", "A1", "Y1", "JF") %in% colnames(df_ovid)))
  expect_true(all(c("TI", "AU", "PY", "JO") %in% colnames(df_econlit)))
  expect_false(any(c("TI", "AU", "PY", "JO") %in% colnames(df_ovid)))
  expect_false(any(c("T1", "A1", "Y1", "JF") %in% colnames(df_econlit)))
})

test_that("two tags mapped to the same semantic field stay separate columns", {
  f <- write_temp_ris(mixed_kw_de_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(df$KW, "alpha")
  expect_equal(df$DE, "beta")
  expect_false("keywords" %in% colnames(df))
})

test_that("a journal recorded under two tags keeps both as separate columns", {
  # JF supplies the main journal, T2 is a series title; today's rename_columns
  # = TRUE path already keeps T2 separate, but calls the JF value "journal"
  f <- write_temp_ris(c(
    "TY  - JOUR",
    "T1  - A chapter",
    "A1  - Black, Kim",
    "Y1  - 2018//",
    "JF  - Journal of Things",
    "T2  - A Series Title",
    "ER  - ",
    ""
  ))
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(df$JF, "Journal of Things")
  expect_equal(df$T2, "A Series Title")
  expect_false("journal" %in% colnames(df))
})

test_that("SP and EP stay separate columns rather than merging into pages", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(df$SP, "419")
  expect_equal(df$EP, "41")
  expect_false("pages" %in% colnames(df))
})

test_that("an end-page-only record has no SP column at all", {
  f <- write_temp_ris(sparse_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(df$EP, "218")
  expect_false("SP" %in% colnames(df))
  expect_false("pages" %in% colnames(df))
})

test_that("rename_columns = TRUE reproduces today's semantic output", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f, rename_columns = TRUE)

  expect_equal(df$title, "Adaptation in the U.S.")
  expect_equal(
    df$author,
    paste("Smith, John A.", "Jones and Partners, Mary B.", sep = ris_sep())
  )
  expect_equal(df$year, "2020")
  expect_equal(df$journal, "Journal of Economics and Statistics")
  expect_equal(df$pages, "419-41")
})

test_that("rename_columns = TRUE on a sparse record matches pre-0.2.0 behaviour", {
  f <- write_temp_ris(sparse_ris())
  on.exit(unlink(f))

  df <- read_ris(f, rename_columns = TRUE)

  expect_equal(df$pages, "-218")
})

test_that("return_df = FALSE keeps raw tags as field names by default", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_equal(recs[[1]]$A1, c("Smith, John A.", "Jones and Partners, Mary B."))
  expect_false("author" %in% names(recs[[1]]))
})

test_that("a repeated tag becomes one vector under that tag", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)

  expect_equal(recs[[1]]$SN, c("0022-1821", "1467-6451"))
  expect_equal(recs[[1]]$M3, c(
    "Climate; Natural Disasters and Their Management; Global Warming [Q54]",
    "Economic Growth and Aggregate Productivity [O40]"
  ))
})

test_that("record labels are the same regardless of rename_columns", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs_raw <- read_ris(f, return_df = FALSE)
  recs_renamed <- read_ris(f, return_df = FALSE, rename_columns = TRUE)

  expect_equal(names(recs_raw), names(recs_renamed))
})

test_that("a Web of Science file defaults to its own raw tags", {
  f <- write_temp_ris(wos_ciw(), ext = ".ciw")
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(df$AU, paste("Smith, J", "Jones, M", sep = ris_sep()))
  expect_equal(df$TI, "A record in Web of Science format")
  expect_equal(df$PY, "2018")
  expect_false(any(c("author", "title", "year") %in% colnames(df)))
})

test_that("a Web of Science file with rename_columns = TRUE matches prior behaviour", {
  f <- write_temp_ris(wos_ciw(), ext = ".ciw")
  on.exit(unlink(f))

  df <- read_ris(f, rename_columns = TRUE)

  expect_equal(df$author, paste("Smith, J", "Jones, M", sep = ris_sep()))
  expect_equal(df$title, "A record in Web of Science format")
  expect_equal(df$year, "2018")
})

test_that("BibTeX output is unaffected by rename_columns", {
  f <- write_temp_ris(c(
    "@ARTICLE{smith2020,",
    "author={Smith, John A.},",
    "title={A study},",
    "year={2020},",
    "}",
    ""
  ), ext = ".bib")
  on.exit(unlink(f))

  df_default <- read_ris(f)
  df_renamed <- read_ris(f, rename_columns = TRUE)

  expect_equal(df_default, df_renamed)
  expect_true("author" %in% colnames(df_default))
})

test_that("a raw-tag read round-trips through write_ris with values intact", {
  f1 <- write_temp_ris(awkward_ris())
  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(c(f1, f2)))

  df1 <- read_ris(f1)
  write_ris(df1, f2)
  df2 <- read_ris(f2)

  for (col in c("T1", "A1", "Y1", "JF", "VL", "IS", "SP", "EP", "SN", "DO")) {
    expect_equal(df2[[col]], df1[[col]], info = col)
  }
})

test_that("a rename_columns = TRUE read round-trips through write_ris with values intact", {
  f1 <- write_temp_ris(awkward_ris())
  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(c(f1, f2)))

  df1 <- read_ris(f1, rename_columns = TRUE)
  write_ris(df1, f2)
  df2 <- read_ris(f2, rename_columns = TRUE)

  expect_equal(df2$title, df1$title)
  expect_equal(df2$author, df1$author)
  expect_equal(df2$pages, df1$pages)
})

test_that("real EBSCO files default to tag-only columns with no keyword loss", {
  skip_if_not(
    dir.exists(test_path("../ebsco_tests")),
    "EBSCO test fixtures not present"
  )
  files <- list.files(test_path("../ebsco_tests"), full.names = TRUE)
  skip_if(length(files) == 0, "no EBSCO test fixtures found")

  f <- files[[1]]
  df <- read_ris(f)

  expect_true("KW" %in% colnames(df))
  expect_false(any(c("keywords", "author", "title", "journal") %in% colnames(df)))

  df_renamed <- read_ris(f, rename_columns = TRUE)
  expect_true("keywords" %in% colnames(df_renamed))

  kw_raw <- lengths(strsplit(df$KW, ris_sep(), fixed = TRUE))
  kw_renamed <- lengths(strsplit(df_renamed$keywords, ris_sep(), fixed = TRUE))
  expect_equal(kw_raw, kw_renamed)
})

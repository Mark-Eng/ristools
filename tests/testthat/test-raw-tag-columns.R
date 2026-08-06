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

test_that("values are carried through under their own tags, unaltered", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f)

  expect_equal(df$T1, "Adaptation in the U.S.")
  expect_equal(
    df$A1,
    paste("Smith, John A.", "Jones and Partners, Mary B.", sep = ris_sep())
  )
  # the year keeps the Ovid "//" suffix the file carries
  expect_equal(df$Y1, "2020//")
  expect_equal(df$JF, "Journal of Economics and Statistics")
})

test_that("return_df = FALSE keeps raw tags as field names", {
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

test_that("records are named by position, and the data frame has no label", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)
  expect_equal(names(recs), "ref_1")

  df <- read_ris(f)
  expect_false("label" %in% colnames(df))
})

test_that("a BibTeX file keeps the field names the file itself uses", {
  f <- write_temp_ris(c(
    "@ARTICLE{smith2020,",
    "author={Smith, John A.},",
    "title={A study},",
    "year={2020},",
    "}",
    ""
  ), ext = ".bib")
  on.exit(unlink(f))

  # BibTeX field names are not RIS tags, so there is no raw tag form to keep:
  # a .bib read is named after its own fields
  df <- read_ris(f)

  expect_true(all(c("author", "title", "year") %in% colnames(df)))
  expect_equal(df$author, "Smith, John A.")
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

test_that("real EBSCO files give tag-only columns with no keyword loss", {
  skip_if_not(
    dir.exists(test_path("../ebsco_tests")),
    "EBSCO test fixtures not present"
  )
  files <- list.files(test_path("../ebsco_tests"), full.names = TRUE)
  skip_if(length(files) == 0, "no EBSCO test fixtures found")

  f <- grep("1-163", files, value = TRUE)[1]
  skip_if(is.na(f), "the 163-record EBSCO fixture is not present")
  df <- read_ris(f)

  expect_true("KW" %in% colnames(df))
  expect_false(any(c("keywords", "author", "title", "journal") %in% colnames(df)))
  # every column is a raw tag, so none is a lower-case semantic name
  expect_true(all(grepl("^[A-Z][A-Z0-9]{1,3}$", colnames(df))))

  # absolute counts, measured before the 0.3.0 refactor. The keyword total is
  # the guarantee the wrapped-tag fix bought: a permissive tag pattern silently
  # truncated or dropped keywords, and the loss showed up only as a lower count.
  expect_equal(nrow(df), 163L)
  kw_counts <- lengths(strsplit(df$KW, ris_sep(), fixed = TRUE))
  expect_equal(sum(kw_counts), 1573L)
})

test_that("ris_sep() is a literal that cannot occur in bibliographic text", {
  expect_equal(ris_sep(), " | ")
})

test_that("every multi-value field is joined with the delimiter", {
  f <- write_temp_ris(awkward_ris())
  on.exit(unlink(f))

  df <- read_ris(f, rename_columns = TRUE)

  # author, M3 and issn all held several values in the source file
  for (fld in c("author", "M3", "issn")) {
    expect_true(
      grepl(ris_sep(), df[[fld]][1], fixed = TRUE),
      info = paste("field:", fld)
    )
  }
})

test_that("ris_to_df() and df_to_ris() are exact inverses", {
  f <- write_temp_ris(c(awkward_ris(), sparse_ris()))
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE)
  round_tripped <- df_to_ris(ris_to_df(recs))

  expect_equal(length(round_tripped), length(recs))
  for (i in seq_along(recs)) {
    # field order and names must both survive
    expect_setequal(names(round_tripped[[i]]), names(recs[[i]]))
    for (nm in names(recs[[i]])) {
      expect_equal(
        round_tripped[[i]][[nm]],
        recs[[i]][[nm]],
        info = paste("record", i, "field", nm)
      )
    }
  }
})

test_that("splitting uses fixed matching, not regex", {
  # if the delimiter were used as a regex, " | " would be an alternation of
  # " " and " " and would split on every character boundary
  df <- data.frame(
    label = "ref_1",
    author = "Smith, J. | Jones, A.",
    stringsAsFactors = FALSE
  )

  recs <- df_to_ris(df)

  expect_length(recs$ref_1$author, 2)
  expect_equal(recs$ref_1$author, c("Smith, J.", "Jones, A."))
})

test_that("a value with no delimiter is left as a single string", {
  df <- data.frame(
    label = "ref_1",
    title = "A study of things",
    stringsAsFactors = FALSE
  )

  recs <- df_to_ris(df)

  expect_length(recs$ref_1$title, 1)
  expect_equal(recs$ref_1$title, "A study of things")
})

test_that("a custom delimiter is honoured in both directions", {
  recs <- structure(
    list(ref_1 = list(author = c("Smith, J.", "Jones, A."))),
    class = "ris_records"
  )

  df <- ris_to_df(recs, delimiter = " ;; ")
  expect_equal(df$author, "Smith, J. ;; Jones, A.")

  back <- df_to_ris(df, delimiter = " ;; ")
  expect_equal(back$ref_1$author, c("Smith, J.", "Jones, A."))
})

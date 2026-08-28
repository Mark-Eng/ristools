test_that("a column that appears once is returned unchanged", {
  df <- data.frame(TY = c("JOUR", NA), TI = c("A study", "Another study"))

  out <- condense_duplicate_cols(df)

  expect_equal(out, df)
})

test_that("the left-most non-NA value wins when both versions have data", {
  df <- cbind(
    data.frame(TY = c("JOUR", "BOOK")),
    data.frame(TY = c("CONF", "CHAP"))
  )

  out <- condense_duplicate_cols(df)

  expect_equal(colnames(out), "TY")
  expect_equal(out$TY, c("JOUR", "BOOK"))
})

test_that("a non-NA value is kept when the other version is blank", {
  df <- cbind(
    data.frame(TY = c(NA, "BOOK")),
    data.frame(TY = c("JOUR", NA))
  )

  out <- condense_duplicate_cols(df)

  expect_equal(out$TY, c("JOUR", "BOOK"))
})

test_that("columns keep the order they first appear in", {
  df <- cbind(
    data.frame(TY = c("JOUR", NA), TI = "A study"),
    data.frame(TY = c(NA, "BOOK"), AB = "An abstract")
  )

  out <- condense_duplicate_cols(df)

  expect_equal(colnames(out), c("TY", "TI", "AB"))
  expect_equal(out$TY, c("JOUR", "BOOK"))
})

test_that("three or more duplicate columns fold left to right", {
  df <- cbind(
    data.frame(TY = c(NA, NA, "A")),
    data.frame(TY = c(NA, "B", "B2")),
    data.frame(TY = c("C", "C2", "C3"))
  )

  out <- condense_duplicate_cols(df)

  expect_equal(out$TY, c("C", "B", "A"))
})

test_that("an empty string is treated as a value, not a blank", {
  df <- cbind(
    data.frame(TY = c("", "BOOK")),
    data.frame(TY = c("JOUR", "CONF"))
  )

  out <- condense_duplicate_cols(df)

  expect_equal(out$TY, c("", "BOOK"))
})

test_that("it refuses input that is not a data frame", {
  expect_error(
    condense_duplicate_cols(list(TY = "JOUR")),
    "data.frame"
  )
})

# Regression tests for two bugs inherited from revtools 0.4.1, both of which
# made every EBSCO Discovery export unreadable or silently corrupt.

# helper: write bytes verbatim, so a BOM or UTF-8 sequence survives
write_bytes <- function(x, ext = ".txt") {
  f <- tempfile(fileext = ext)
  con <- file(f, open = "wb")
  writeBin(charToRaw(x), con)
  close(con)
  f
}

utf8_record <- paste0(
  "TY  - JOUR\r\n",
  "TI  - Does digitalisation help achieve socio‐economic SDGs?\r\n",
  "AU  - Gonçalves, Maria\r\n",
  "AU  - Thøgersen, John\r\n",
  "AU  - Charłampowicz, Jędrzej\r\n",
  "PY  - 2024\r\n",
  "JO  - Sustainable Development\r\n",
  "ER  - \r\n\r\n"
)

test_that("a BOM-prefixed file reads without error", {
  # The BOM is three bytes (EF BB BF) prefixed to the first tag. Marking the
  # text latin1 turned them into three visible characters, so the first tag
  # stopped matching under the C locale that read_ris sets. The opening record
  # lost its tag, prep_ris() found one fewer start than end, and the read died
  # with "arguments imply differing number of rows: n-1, n".
  f <- write_bytes(paste0("﻿", utf8_record))
  on.exit(unlink(f))

  expect_no_error(df <- read_ris(f))
  expect_equal(nrow(df), 1)
})

test_that("a BOM does not end up in the first field's value", {
  f <- write_bytes(paste0("﻿", utf8_record))
  on.exit(unlink(f))

  df <- read_ris(f, rename_columns = TRUE)
  expect_equal(df$type, "JOUR")
  expect_false(grepl("﻿", df$type, fixed = TRUE))
})

test_that("BOM and non-BOM versions of a file parse identically", {
  f1 <- write_bytes(utf8_record)
  f2 <- write_bytes(paste0("﻿", utf8_record))
  on.exit(unlink(c(f1, f2)))

  d1 <- read_ris(f1)
  d2 <- read_ris(f2)

  expect_equal(d1, d2)
})

test_that("a multi-record BOM file finds every record", {
  body <- paste(rep(utf8_record, 5), collapse = "")
  f <- write_bytes(paste0("﻿", body))
  on.exit(unlink(f))

  df <- read_ris(f)
  expect_equal(nrow(df), 5)
})

test_that("UTF-8 text is not mojibaked", {
  # Encoding() was hardcoded to "latin1", so every multi-byte character was
  # reinterpreted bytewise: a U+2010 hyphen became "a" and an
  # e-acute became two characters. Ovid exports are pure ASCII, which is why
  # this went unnoticed.
  f <- write_bytes(utf8_record)
  on.exit(unlink(f))

  df <- read_ris(f, rename_columns = TRUE)

  expect_true(grepl("socio‐economic", df$title, fixed = TRUE))
  # the classic mojibake signature: "a" + euro sign
  expect_false(grepl("â€", df$title))
})

test_that("accented author names survive", {
  f <- write_bytes(utf8_record)
  on.exit(unlink(f))

  recs <- read_ris(f, return_df = FALSE, rename_columns = TRUE)
  authors <- recs[[1]]$author

  expect_length(authors, 3)
  expect_true(any(grepl("Gonçalves", authors)))
  expect_true(any(grepl("Thøgersen", authors)))
  expect_true(any(grepl("Charłampowicz", authors)))
})

test_that("latin1 files still read correctly", {
  # a latin1 file is not valid UTF-8, so it must still be treated as latin1
  latin1_bytes <- paste0(
    "TY  - JOUR\r\n",
    "TI  - Caf", rawToChar(as.raw(0xe9)), " culture\r\n",
    "AU  - Se", rawToChar(as.raw(0xf1)), "or, Juan\r\n",
    "PY  - 2020\r\n",
    "ER  - \r\n\r\n"
  )
  f <- write_bytes(latin1_bytes)
  on.exit(unlink(f))

  df <- read_ris(f, rename_columns = TRUE)
  expect_equal(nrow(df), 1)
  expect_true(grepl("Café", df$title))
})

test_that("reading a file with non-ASCII labels raises no warnings", {
  # rbind() took row names from the record labels and warned once per record
  # that it could not translate them to the native encoding
  body <- paste(rep(utf8_record, 3), collapse = "")
  f <- write_bytes(body)
  on.exit(unlink(f))

  expect_no_warning(read_ris(f))
})

test_that("non-ASCII text survives a full round trip", {
  f1 <- write_bytes(utf8_record)
  f2 <- tempfile(fileext = ".ris")
  on.exit(unlink(c(f1, f2)))

  d1 <- read_ris(f1, rename_columns = TRUE)
  write_ris(d1, f2)
  d2 <- read_ris(f2, rename_columns = TRUE)

  expect_equal(d1$title, d2$title)
  expect_equal(d1$author, d2$author)
})

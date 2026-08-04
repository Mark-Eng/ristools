make_numbered_ris <- function(n) {
  unlist(lapply(seq_len(n), function(i) {
    c("TY  - JOUR", paste0("T1  - Record ", i), "ER  - ")
  }))
}

test_that("a file is split into the expected number of chunks", {
  f <- write_temp_ris(make_numbered_ris(5))
  out <- file.path(tempdir(), paste0("chunks_", basename(tempfile())))
  on.exit(unlink(c(f, out), recursive = TRUE))

  paths <- split_ris_file(f, out, set_size = 2)

  expect_length(paths, 3) # 2 + 2 + 1
  expect_true(all(file.exists(paths)))
})

test_that("chunk file names carry the record range", {
  f <- write_temp_ris(make_numbered_ris(3))
  out <- file.path(tempdir(), paste0("chunks_", basename(tempfile())))
  on.exit(unlink(c(f, out), recursive = TRUE))

  paths <- split_ris_file(f, out, set_size = 2)

  expect_match(basename(paths[1]), "\\(1-2\\)\\.ris$")
  expect_match(basename(paths[2]), "\\(3-3\\)\\.ris$")
})

test_that("no records are lost or altered by splitting", {
  f <- write_temp_ris(make_numbered_ris(5))
  out <- file.path(tempdir(), paste0("chunks_", basename(tempfile())))
  on.exit(unlink(c(f, out), recursive = TRUE))

  paths <- split_ris_file(f, out, set_size = 2)

  recombined <- unlist(lapply(paths, readLines))
  titles <- grep("^T1  - ", recombined, value = TRUE)

  expect_length(titles, 5)
  expect_equal(titles, paste0("T1  - Record ", 1:5))
})

test_that("an existing parenthesised suffix is not duplicated", {
  lines <- make_numbered_ris(2)
  f <- file.path(tempdir(), "export (1-2).ris")
  writeLines(lines, f)
  out <- file.path(tempdir(), paste0("chunks_", basename(tempfile())))
  on.exit(unlink(c(f, out), recursive = TRUE))

  paths <- split_ris_file(f, out, set_size = 1)

  expect_match(basename(paths[1]), "^export \\(1-1\\)\\.ris$")
})

test_that("mismatched TY and ER counts are rejected", {
  f <- write_temp_ris(c("TY  - JOUR", "T1  - Unclosed record"))
  on.exit(unlink(f))

  expect_error(
    split_ris_file(f, file.path(tempdir(), "nope")),
    "do not match"
  )
})

test_that("a file with no TY lines is rejected", {
  f <- write_temp_ris(c("not a ris file", "just some text"))
  on.exit(unlink(f))

  expect_error(
    split_ris_file(f, file.path(tempdir(), "nope")),
    "no 'TY"
  )
})

test_that("a missing input file is rejected", {
  expect_error(
    split_ris_file(tempfile(), tempdir()),
    "input file not found"
  )
})

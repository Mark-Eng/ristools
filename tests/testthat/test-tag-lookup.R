# The tag table is reference data for callers, and the source of the canonical
# field order write_ris() emits. These tests pin its shape and that order: the
# reader does not consult the table to name columns, so a change here cannot
# alter how a file parses, but it can change the order of a written file.

test_that("the table has one row per tag and three columns", {
  expect_equal(dim(ris_tag_lookup()), c(42L, 3L))
  expect_equal(colnames(ris_tag_lookup()), c("ris", "bib", "order"))
})

test_that("the order column is the field's position in the definition list", {
  tbl <- ris_tag_lookup()

  expect_type(tbl$order, "integer")
  expect_equal(tbl$order[tbl$ris == "TY"], 1L)
  # all seven journal tags share one position
  expect_equal(unique(tbl$order[tbl$bib == "journal"]), 6L)
  expect_equal(max(tbl$order), 24L)
})

test_that("the table takes no arguments", {
  # 0.3.0 dropped the type argument along with the medline, wos and ris_write
  # tables; see inst/notes/reintroducing-semantic-fields.md
  expect_length(formals(ris_tag_lookup), 0L)
})

test_that("several tags share a field name, which is why they stay separate", {
  tbl <- ris_tag_lookup()

  expect_setequal(
    tbl$ris[tbl$bib == "journal"],
    c("JO", "T2", "T3", "SO", "JT", "JF", "JA")
  )
  expect_setequal(tbl$ris[tbl$bib == "pages"], c("EP", "BP", "SP"))
  expect_setequal(
    tbl$ris[tbl$bib == "author"],
    c("AU", "A1", "A2", "A3", "A4", "A5")
  )
})

test_that("ED is listed twice, as both editor and edition", {
  # a genuine ambiguity in the RIS conventions, left for the caller to resolve.
  # It is inert here: nothing merges tags to fields, so no file is affected.
  tbl <- ris_tag_lookup()
  ed <- tbl[tbl$ris == "ED", ]

  expect_equal(nrow(ed), 2)
  expect_setequal(ed$bib, c("editor", "edition"))
})

test_that("ED is the only tag listed more than once", {
  tbl <- ris_tag_lookup()

  expect_equal(unique(tbl$ris[duplicated(tbl$ris)]), "ED")
})

test_that("the table is plain character data with default row names", {
  tbl <- ris_tag_lookup()

  expect_type(tbl$ris, "character")
  expect_type(tbl$bib, "character")
  expect_equal(rownames(tbl), as.character(seq_len(nrow(tbl))))
})

test_that("every tag in the table has the shape the reader recognises", {
  # two characters: a capital, then a capital or a digit
  expect_true(all(grepl("^[A-Z][A-Z0-9]$", ris_tag_lookup()$ris)))
})

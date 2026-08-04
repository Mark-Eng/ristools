# These tests pin the tag tables to the values inherited from revtools 0.4.1.
# They are not testing "correct" mappings -- several are demonstrably odd (see
# below) -- but changing any of them changes how existing files parse, so they
# must only ever change deliberately.

test_that("each table has the expected dimensions", {
  expect_equal(dim(ris_tag_lookup("ris")), c(42L, 3L))
  expect_equal(dim(ris_tag_lookup("ris_write")), c(25L, 2L))
  expect_equal(dim(ris_tag_lookup("medline")), c(67L, 2L))
  expect_equal(dim(ris_tag_lookup("wos")), c(82L, 2L))
})

test_that("the order column exists only for type = 'ris'", {
  expect_true("order" %in% colnames(ris_tag_lookup("ris")))
  expect_false("order" %in% colnames(ris_tag_lookup("ris_write")))
  expect_false("order" %in% colnames(ris_tag_lookup("medline")))
  expect_false("order" %in% colnames(ris_tag_lookup("wos")))
})

test_that("the order column is the field's position in the definition list", {
  tbl <- ris_tag_lookup("ris")

  expect_type(tbl$order, "integer")
  expect_equal(tbl$order[tbl$ris == "TY"], 1L)
  # all seven journal tags share one position
  expect_equal(unique(tbl$order[tbl$bib == "journal"]), 6L)
  expect_equal(max(tbl$order), 24L)
})

test_that("ris defaults to type = 'ris'", {
  expect_equal(ris_tag_lookup(), ris_tag_lookup("ris"))
})

test_that("an unknown type is rejected", {
  expect_error(ris_tag_lookup("nonsense"))
})

test_that("upstream typos are preserved verbatim", {
  # correcting either of these would silently orphan any code keying on them
  medline <- ris_tag_lookup("medline")
  expect_equal(medline$bib[medline$ris == "PMC"], "pubmed_central_identitfier")

  wos <- ris_tag_lookup("wos")
  expect_equal(wos$bib[wos$ris == "WC"], "wos_cagegories")
})

test_that("ED maps to both editor and edition in the ris table", {
  # An upstream bug, preserved deliberately: because the tag-to-field merge is
  # many-to-many, every ED line in a file is read as two fields. Fixing it is
  # a separate change and needs its own decision about which ED means what.
  tbl <- ris_tag_lookup("ris")
  ed <- tbl[tbl$ris == "ED", ]

  expect_equal(nrow(ed), 2)
  expect_setequal(ed$bib, c("editor", "edition"))
})

test_that("ED is the only duplicated tag in any table", {
  for (ty in c("ris", "ris_write", "medline", "wos")) {
    tbl <- ris_tag_lookup(ty)
    dups <- unique(tbl$ris[duplicated(tbl$ris)])
    expected <- if (ty == "ris") "ED" else character(0)
    expect_equal(dups, expected, info = paste("type:", ty))
  }
})

test_that("wos maps two tags each to file_name and pages", {
  wos <- ris_tag_lookup("wos")

  expect_setequal(wos$ris[wos$bib == "file_name"], c("FN", "N"))
  expect_setequal(wos$ris[wos$bib == "pages"], c("BP", "EP"))
})

test_that("medline maps both CRDT and DA to date_created", {
  medline <- ris_tag_lookup("medline")

  expect_setequal(medline$ris[medline$bib == "date_created"], c("CRDT", "DA"))
})

test_that("the tables are plain character data with default row names", {
  for (ty in c("ris", "ris_write", "medline", "wos")) {
    tbl <- ris_tag_lookup(ty)
    expect_type(tbl$ris, "character")
    expect_type(tbl$bib, "character")
    # merge() in the read path keys on 'ris'; stray row names would survive
    # into the merged frame and confuse ordering
    expect_equal(rownames(tbl), as.character(seq_len(nrow(tbl))))
  }
})
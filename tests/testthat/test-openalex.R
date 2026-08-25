# ============================================================================
#  OpenAlex -> data frame -> RIS
#
#  fixtures/openalex_works.json is a four-record API response covering the
#  shapes that broke a naive conversion:
#   [1] every list field populated, three authors (one plain, one with a
#       lower-case particle, one already inverted), two topics sharing a
#       subfield, two SDGs, an abstract to rebuild
#   [2] every list field an empty array, every optional scalar null
#   [3] almost every field absent, as a `select=` query returns
#   [4] a work type not in oa_ris_types(), and the legacy "keyword" spelling
# ============================================================================

oa_fixture <- function() {
  testthat::test_path("fixtures", "openalex_works.json")
}


# Record 4 has a work type oa_ris_types() does not cover, so every ris_tags
# conversion of this fixture warns. That warning has its own test; everywhere
# else it is noise.
oa_ris_fixture <- function(...) {
  suppressWarnings(oa2risdf(oa_fixture(), ris_tags = TRUE, ...))
}


# -------------------------------------------------------------- oa2risdf() --

test_that("the five nested fields become delimited strings", {
  df <- oa2risdf(oa_fixture())

  expect_s3_class(df, "data.frame")
  expect_equal(nrow(df), 4)

  expect_equal(
    df$authorships[1],
    "Massimo Aria | Ludo van der Berg | Cuccurullo, Corrado"
  )
  expect_equal(df$concepts[1], "Citation | Computer science")
  expect_equal(df$keywords[1], "Science Mapping | Bibliometrics")
  expect_equal(
    df$sustainable_development_goals[1],
    "Quality education | Industry, innovation and infrastructure"
  )
})

test_that("no column is a list column", {
  df <- oa2risdf(oa_fixture())

  # the whole point: write_ris() coerces with as.character(), which deparses a
  # list column into "list(id = c(...), display_name = c(...))"
  expect_true(all(vapply(df, is.atomic, logical(1))))
  expect_false(any(vapply(df, is.list, logical(1))))
})

test_that("topic_levels keeps only the levels asked for", {
  df <- oa2risdf(oa_fixture())

  # the default drops the field and domain rows
  expect_equal(
    df$topics[1],
    paste(
      "Scientometrics and Bibliometrics Research",
      "Library and Information Sciences",
      "Data Analysis with R",
      sep = " | "
    )
  )
  # the two topics share a subfield, which is not repeated
  expect_equal(lengths(regmatches(
    df$topics[1],
    gregexpr("Library and Information Sciences", df$topics[1], fixed = TRUE)
  ))[[1]], 1)

  all_levels <- oa2risdf(oa_fixture(), topic_levels = NULL)
  expect_true(grepl("Computer Science", all_levels$topics[1], fixed = TRUE))
  expect_true(grepl("Physical Sciences", all_levels$topics[1], fixed = TRUE))

  just_topics <- oa2risdf(oa_fixture(), topic_levels = "topic")
  expect_equal(
    just_topics$topics[1],
    "Scientometrics and Bibliometrics Research | Data Analysis with R"
  )
})

test_that("author order is kept and duplicate names are not dropped", {
  works <- list(list(
    id = "W1",
    title = "Two people with the same name",
    publication_year = 2020L,
    authorships = list(
      list(author = list(display_name = "Zoe Adams")),
      list(author = list(display_name = "Alan Brown")),
      list(author = list(display_name = "Zoe Adams"))
    )
  ))

  # not sorted, and not de-duplicated: dropping the third would lose an author
  expect_equal(oa2risdf(works)$authorships, "Zoe Adams | Alan Brown | Zoe Adams")
})

test_that("empty arrays and absent fields both give NA, never the string 'NA'", {
  df <- oa2risdf(oa_fixture())

  # record 2 has every list field as [], record 3 omits them entirely
  for (cl in c(
    "authorships", "concepts", "topics", "keywords",
    "sustainable_development_goals", "abstract"
  )) {
    expect_true(is.na(df[[cl]][2]), info = paste("empty array:", cl))
    expect_true(is.na(df[[cl]][3]), info = paste("absent field:", cl))
  }
  expect_false(any(vapply(df, function(v) any(v %in% "NA"), logical(1))))
})

test_that("the abstract is rebuilt from the inverted index", {
  df <- oa2risdf(oa_fixture())

  expect_equal(df$abstract[1], "This paper describes bibliometrix.")
  # absent stays absent rather than becoming ""
  expect_true(is.na(df$abstract[2]))
})

test_that("abstract = FALSE drops the column rather than emptying it", {
  df <- oa2risdf(oa_fixture(), abstract = FALSE)

  expect_false("abstract" %in% colnames(df))
})

test_that("the legacy 'keyword' spelling is still read", {
  df <- oa2risdf(oa_fixture())

  # record 4 uses {"keyword": ...} rather than {"display_name": ...}
  expect_equal(df$keywords[4], "legacy keyword form")
})

test_that("scalar fields are read from the right sub-object", {
  df <- oa2risdf(oa_fixture())

  expect_equal(df$source_display_name[1], "Journal of Informetrics")
  expect_equal(df$issn_l[1], "1751-1577")
  expect_equal(df$first_page[1], "959")
  expect_equal(df$last_page[1], "975")
  expect_equal(df$volume[1], "11")
  expect_equal(df$issue[1], "4")
  expect_equal(df$publication_year[1], 2017L)
  expect_equal(df$cited_by_count[1], 9999L)
  expect_equal(df$fwci[1], 12.5)
  expect_false(df$is_oa[1])
  expect_true(df$is_oa_anywhere[2])
  # a character date, not a Date -- see the roxygen for oa2risdf()
  expect_type(df$publication_date, "character")
  expect_equal(df$publication_date[1], "2017-11-01")
})


# ------------------------------------------------------------ input forms --

test_that("every accepted input form gives the same data frame", {
  path <- oa_fixture()
  envelope <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  works <- envelope$results

  from_path <- oa2risdf(path)
  expect_equal(oa2risdf(envelope), from_path)
  expect_equal(oa2risdf(works), from_path)
  expect_equal(oa2risdf(readChar(path, file.info(path)$size)), from_path)

  # a paged fetch, saved page by page
  paged <- list(
    list(meta = list(page = 1), results = works[1:2]),
    list(meta = list(page = 2), results = works[3:4])
  )
  expect_equal(oa2risdf(paged), from_path)

  # a single work, fetched by id
  expect_equal(oa2risdf(works[[1]]), from_path[1, ])
})

test_that("an empty result gives a zero-row frame, not an error", {
  empty <- oa2risdf(list(meta = list(count = 0), results = list()))

  expect_equal(nrow(empty), 0)
  expect_true("authorships" %in% colnames(empty))
})

test_that("a non-works entity is refused rather than converted to NAs", {
  authors <- list(list(
    id = "https://openalex.org/A5048491430",
    display_name = "Massimo Aria",
    works_count = 120L,
    cited_by_count = 5000L
  ))

  expect_error(oa2risdf(authors), "OpenAlex \\*works\\*")
})

test_that("a string that is neither a file nor JSON is refused", {
  expect_error(oa2risdf("not json and not a file"), "neither an existing file")
  expect_error(oa2risdf(c("a", "b")), "not a vector")
})


# ----------------------------------------------------------- oa2ristags() --

test_that("columns are renamed to the tags in oa_ris_tags()", {
  out <- oa_ris_fixture()
  m <- oa_ris_tags()

  expect_equal(colnames(out)[seq_len(nrow(m))], m$ris)
  expect_false(any(m$oa %in% colnames(out)))
})

test_that("the ris_tags argument and the standalone function agree", {
  # one implementation, two entry points: this is what pins that
  standalone <- function(...) suppressWarnings(oa2ristags(oa2risdf(oa_fixture()), ...))

  expect_identical(oa_ris_fixture(), standalone())
  expect_identical(
    oa_ris_fixture(invert_authors = FALSE),
    standalone(invert_authors = FALSE)
  )
})

test_that("URL prefixes are stripped from id and doi", {
  out <- oa_ris_fixture()

  expect_equal(out$ID[1], "W2755950973")
  expect_equal(out$DO[1], "10.1016/j.joi.2017.08.007")
  expect_true(is.na(out$DO[2]))
})

test_that("N1 and U3 are prefixed once per value", {
  out <- oa_ris_fixture()

  expect_equal(out$N1[1], "Cited by: 9999")
  # write_ris() writes one line per value, so each value carries the label
  expect_equal(
    out$U3[1],
    "SDGs: Quality education | SDGs: Industry, innovation and infrastructure"
  )
  expect_true(is.na(out$U3[2]))
})

test_that("running oa2ristags twice does not double a prefix", {
  once <- oa_ris_fixture()
  expect_message(twice <- oa2ristags(once), "already named with RIS tags")

  expect_identical(once, twice)
  expect_false(any(grepl("Cited by: Cited by:", twice$N1, fixed = TRUE)))
})

test_that("a frame with no recognised columns warns and is returned intact", {
  df <- data.frame(alpha = 1, beta = 2)

  expect_warning(out <- oa2ristags(df), "no OpenAlex columns recognised")
  expect_identical(out, df)
})

test_that("unmapped columns are kept for write_ris to drop", {
  out <- oa_ris_fixture()

  # oa2ristags() renames; write_ris() is the single place that decides what
  # reaches a file
  expect_true("fwci" %in% colnames(out))
  expect_true("referenced_works" %in% colnames(out))
})

test_that("oa2ristags refuses anything that is not a data frame", {
  expect_error(oa2ristags(1:10), "data.frame")
})


# ------------------------------------------------------------ type recode --

test_that("OpenAlex work types become RIS reference types", {
  out <- oa_ris_fixture()

  expect_equal(out$TY[1], "JOUR")
  expect_equal(out$TY[2], "CHAP")
  expect_equal(out$TY[3], "JOUR") # peer-review appears in a journal
})

test_that("an unknown or missing type becomes GEN, with a warning", {
  # deliberately not oa_ris_fixture(): the warning is the subject here
  expect_warning(
    out <- oa2risdf(oa_fixture(), ris_tags = TRUE),
    "video-essay"
  )
  expect_equal(out$TY[4], "GEN")

  df <- data.frame(type = NA_character_, title = "x", stringsAsFactors = FALSE)
  expect_warning(out2 <- oa2ristags(df), "<missing>")
  # a record with no TY has no opening tag, and readers find records by it
  expect_equal(out2$TY, "GEN")
})

test_that("every mapped type is a real RIS reference type", {
  types <- oa_ris_types()

  expect_true(all(nzchar(types$openalex)))
  expect_false(anyDuplicated(types$openalex) > 0)
  expect_true(all(grepl("^[A-Z]+$", types$ris)))
})


# --------------------------------------------------------- author inversion --

test_that("author names are inverted to Family, Given", {
  out <- oa_ris_fixture()

  expect_equal(
    out$AU[1],
    "Aria, Massimo | van der Berg, Ludo | Cuccurullo, Corrado"
  )
})

test_that("invert_authors = FALSE leaves names exactly as OpenAlex gave them", {
  out <- oa_ris_fixture(invert_authors = FALSE)

  expect_equal(
    out$AU[1],
    "Massimo Aria | Ludo van der Berg | Cuccurullo, Corrado"
  )
})

test_that("name inversion follows its documented rules", {
  invert <- function(x) oa_invert_author_field(x, ris_sep())

  expect_equal(invert("Massimo Aria"), "Aria, Massimo")
  expect_equal(invert("J. Smith"), "Smith, J.")

  # lower-case particles join the family name; the rule BibTeX uses
  expect_equal(invert("Ludo van der Berg"), "van der Berg, Ludo")
  expect_equal(invert("Maria de la Cruz"), "de la Cruz, Maria")
  # a capitalised one does not, so "Della" stays a given name
  expect_equal(invert("Della Rosa"), "Rosa, Della")

  # a suffix stays with the family name
  expect_equal(invert("John Smith Jr."), "Smith Jr., John")

  # left alone: already inverted, and a single token
  expect_equal(invert("Aria, Massimo"), "Aria, Massimo")
  expect_equal(invert("UNICEF"), "UNICEF")

  # a particle can never consume the whole name
  expect_equal(invert("van Berg"), "Berg, van")

  expect_true(is.na(invert(NA_character_)))
})


# ------------------------------------------------------------- end to end --

test_that("OpenAlex JSON survives oa2risdf -> write_ris -> read_ris", {
  out <- oa_ris_fixture()

  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))
  suppressWarnings(write_ris(out, f))

  back <- read_ris(f)

  expect_equal(nrow(back), 4)
  expect_equal(back$TY[1], "JOUR")
  expect_equal(back$ID[1], "W2755950973")
  # the delimiter oa2risdf() joins with is the one write_ris() splits on, so a
  # three-author paper writes three AU lines and reads back as three values
  expect_equal(
    back$AU[1],
    "Aria, Massimo | van der Berg, Ludo | Cuccurullo, Corrado"
  )
  expect_equal(back$KW[1], "Science Mapping | Bibliometrics")
  expect_equal(back$U1[1], "Citation | Computer science")
  expect_equal(back$N1[1], "Cited by: 9999")
  expect_equal(back$SP[1], "959")
  expect_equal(back$EP[1], "975")
})

test_that("the written file contains no deparsed list and no literal NA", {
  out <- oa_ris_fixture()

  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))
  suppressWarnings(write_ris(out, f))
  lines <- readLines(f, warn = FALSE)

  expect_false(any(grepl("list(", lines, fixed = TRUE)))
  expect_false(any(grepl("^[A-Z][A-Z0-9]  - NA$", lines)))
})

test_that("a record with almost every field absent still writes a valid entry", {
  out <- oa_ris_fixture()

  f <- tempfile(fileext = ".ris")
  on.exit(unlink(f))
  suppressWarnings(write_ris(out[3, ], f))
  lines <- readLines(f, warn = FALSE)

  # TY first and ER last is what makes a record findable. Records are
  # separated by a blank line, so the file ends with one.
  expect_equal(lines[1], "TY  - JOUR")
  expect_equal(utils::tail(lines[nzchar(lines)], 1), "ER  -")
  expect_equal(read_ris(f)$TI, "A record with almost every field absent")
})

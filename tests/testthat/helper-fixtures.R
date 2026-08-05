# A record that exercises every known regression at once:
#  - an author containing " and " (must not be split on it)
#  - EconLit M3 descriptors that contain " and " and end in a JEL code
#  - SP 419 / EP 41, an abbreviated end page that sort() would reverse
#  - a title ending in a full stop after an initialism
#  - a multi-value SN
awkward_ris <- function() {
  c(
    "TY  - JOUR",
    "T1  - Adaptation in the U.S.",
    "A1  - Smith, John A.",
    "A1  - Jones and Partners, Mary B.",
    "Y1  - 2020//",
    "N2  - An abstract about climate and growth.",
    "JF  - Journal of Economics and Statistics",
    "VL  - 12",
    "IS  - 3",
    "SP  - 419",
    "EP  - 41",
    "M3  - Climate; Natural Disasters and Their Management; Global Warming [Q54]",
    "M3  - Economic Growth and Aggregate Productivity [O40]",
    "SN  - 0022-1821",
    "SN  - 1467-6451",
    "DO  - 10.1111/joes.12345",
    "ER  - ",
    ""
  )
}

# a second record with no abstract, no volume, and an end page but no start
sparse_ris <- function() {
  c(
    "TY  - JOUR",
    "T1  - A record with no abstract",
    "A1  - Brown, Alice",
    "Y1  - 2019//",
    "JF  - Review of Nothing",
    "EP  - 218",
    "ER  - ",
    ""
  )
}

# An EBSCO-style record whose KW and AB fields wrap across lines without
# repeating the tag. The continuation lines cover every class of value that the
# old permissive tag pattern misparsed:
#  - "E7 economies": a tag-like first word, truncated to "economies"
#  - "EKC" / "GHG": a whole-line tag-like value, dropped outright
#  - "F34" / "Q54": JEL codes, split into "F3" + "4" and "Q5" + "4"
#  - "CO2 emissions" in the abstract, torn out into a bogus CO2 field
#  - ordinary lines, which must be left alone
wrapped_kw_ris <- function() {
  c(
    "TY  - JOUR",
    "T1  - Wrapped keyword fields",
    "A1  - Adeleye, Bosede Ngozi",
    "Y1  - 2025//",
    "JF  - Journal of Wrapping",
    "AB  - An abstract that wraps mid-field.",
    "CO2 emissions are discussed at length.",
    "KW  - Carbon emissions",
    "E7 economies",
    "EKC",
    "GHG",
    "F34",
    "Q54",
    "Non-renewable",
    "M3  - Article",
    "ER  - ",
    ""
  )
}

# the keywords wrapped_kw_ris() must yield, in file order
wrapped_kw_expected <- function() {
  c(
    "Carbon emissions",
    "E7 economies",
    "EKC",
    "GHG",
    "F34",
    "Q54",
    "Non-renewable"
  )
}

# a Web of Science .ciw record: two-character tags with a single space and no
# hyphen, plus an indented continuation line
wos_ciw <- function() {
  c(
    "FN Clarivate Analytics Web of Science",
    "VR 1.0",
    "PT J",
    "AU Smith, J",
    "   Jones, M",
    "TI A record in Web of Science format",
    "SO JOURNAL OF THINGS",
    "PY 2018",
    "ER",
    ""
  )
}

# the same record as awkward_ris(), tagged EconLit-style (AU/TI/PY/JO) rather
# than Ovid-style (A1/T1/Y1/JF), so the two can be compared to show that raw
# tag output follows the source file's own tags rather than a fixed schema
econlit_ris <- function() {
  c(
    "TY  - JOUR",
    "TI  - Adaptation in the U.S.",
    "AU  - Smith, John A.",
    "AU  - Jones and Partners, Mary B.",
    "PY  - 2020",
    "AB  - An abstract about climate and growth.",
    "JO  - Journal of Economics and Statistics",
    "VL  - 12",
    "IS  - 3",
    "SP  - 419",
    "EP  - 41",
    "DO  - 10.1111/joes.12345",
    "ER  - ",
    ""
  )
}

# a record whose KW block mixes two different tags mapped to the same
# semantic field ("keywords" = KW or DE), to verify both survive as distinct
# raw-tag columns rather than merging
mixed_kw_de_ris <- function() {
  c(
    "TY  - JOUR",
    "T1  - Mixed keyword tags",
    "A1  - Green, Robin",
    "Y1  - 2022//",
    "KW  - alpha",
    "DE  - beta",
    "ER  - ",
    ""
  )
}

# write lines to a temp .ris file and return the path
write_temp_ris <- function(lines, ext = ".ris") {
  f <- tempfile(fileext = ext)
  writeLines(lines, f)
  f
}
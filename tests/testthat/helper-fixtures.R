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

# write lines to a temp .ris file and return the path
write_temp_ris <- function(lines, ext = ".ris") {
  f <- tempfile(fileext = ext)
  writeLines(lines, f)
  f
}
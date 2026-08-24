library(tidyverse)
library(openalexR)

measure_pov <- oa_request(
  "https://api.openalex.org/?oql=works%20where%20title/abstract%20has%20(within%204%20(%22poverty%22,%20%22measur*%22))%20and%20title/abstract%20has%20(not%20(%22energy%20poverty%22%20OR%20%22data%20poverty%22%20OR%20%22digital%20poverty%22%20OR%20%22transport%20poverty%22%20OR%20%22fuel%20poverty%22%20OR%20%22period%20poverty%22%20OR%20%22menstrual%20poverty%22%20OR%20%22information%20poverty%22))%20and%20citation%20count%20%3E%20(99)"
)

measure_pov_df <- ristools::oa2df(measure_pov)

measure_pov_ris <- measure_pov_df %>%
  oa2ristags()

write_ris(
  measure_pov_ris,
  "C:/Users/ME/Code/R/info_retrieval/input_files/measure_poverty_papers.ris"
)

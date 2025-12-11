# clean_data.R

library(dplyr)
library(readr)
library(lubridate)
library(stringr)

if (!file.exists("week_data_raw.csv")) stop("week_data_raw.csv not found")

new_raw <- read_csv("week_data_raw.csv", show_col_types = FALSE)

# normalize refs column to comma-separated string
new_raw <- new_raw %>% mutate(refs = sapply(refs, function(x) {
  if (is.list(x) || is.vector(x)) paste(unlist(x), collapse = ", ") else as.character(x)
}))

# Ensure date is Date type
new_raw <- new_raw %>% mutate(date = as.Date(date))

# Load existing persistent DB if exists, else empty
if (file.exists("ref_bias_data.csv")) {
  existing <- read_csv("ref_bias_data.csv", show_col_types = FALSE) %>% mutate(date = as.Date(date))
} else existing <- tibble()

# Combine and deduplicate by url (url uniquely identifies a game)
combined <- bind_rows(existing, new_raw) %>%
  arrange(date) %>%
  distinct(url, .keep_all = TRUE)

# Save
write_csv(combined, "ref_bias_data.csv")
cat("Updated ref_bias_data.csv rows:", nrow(combined), "\n")

#scraper.R

library(rvest)
library(httr)
library(dplyr)
library(stringr)
library(purrr)
library(lubridate)

# ---------------------------------------------------------
# HELPER: GET PAGE WITH PROPER HEADERS AND RETRY LOGIC
# ---------------------------------------------------------
get_page <- function(url, max_retries = 3) {
  for (attempt in 1:max_retries) {
    # Add realistic browser headers
    response <- try(GET(
      url,
      add_headers(
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" = "en-US,en;q=0.5",
        "Accept-Encoding" = "gzip, deflate",
        "DNT" = "1",
        "Connection" = "keep-alive"
      )
    ), silent = TRUE)
    
    if (inherits(response, "try-error")) {
      if (attempt < max_retries) {
        Sys.sleep(6 + runif(1, 0, 4))   # 6–10 seconds between each DATE PAGE
        next
      }
      return(NULL)
    }
    
    status <- status_code(response)
    
    if (status == 200) {
      return(read_html(response))
    } else if (status == 429) {
      wait_time <- 60 * attempt  # Wait longer each retry (60s, 120s, 180s)
      cat("⚠️  Rate limited (429). Waiting", wait_time, "seconds before retry", attempt, "/", max_retries, "\n")
      Sys.sleep(wait_time)
    } else {
      if (attempt < max_retries) {
        Sys.sleep(6 + runif(1, 0, 4))   # 6–10 seconds between each DATE PAGE
        next
      }
      cat("ERROR: HTTP status", status, "for", url, "\n")
      return(NULL)
    }
  }
  
  cat("ERROR: Failed after", max_retries, "retries\n")
  return(NULL)
}

# ---------------------------------------------------------
# 1. GET DAILY BOX SCORE LINKS
# ---------------------------------------------------------
get_boxscore_links <- function(month, day, year) {
  
  url <- paste0(
    "https://www.basketball-reference.com/boxscores/?month=",
    month, "&day=", day, "&year=", year
  )
  
  cat("Fetching:", url, "\n")
  
  page <- get_page(url)
  
  if (is.null(page)) {
    cat("⚠️ Could not load page: ", url, "\n")
    return(character(0))
  }
  
  # Find all "Box Score" links (more reliable selector)
  links <- page %>%
    html_nodes("p.links a") %>%
    {.[html_text(.) == "Box Score"]} %>%
    html_attr("href")
  
  if (length(links) == 0) {
    cat("No games found on ", paste(year, month, day, sep = "-"), "\n")
    return(character(0))
  }
  
  full_links <- paste0("https://www.basketball-reference.com", links)
  cat("Found", length(full_links), "games\n")
  
  return(full_links)
}

# ---------------------------------------------------------
# 2. SCRAPE A SINGLE GAME
# ---------------------------------------------------------
scrape_game <- function(box_url) {
  
  
  pg <- get_page(box_url, max_retries = 5)
  if (is.null(pg)) {
    cat("❌ Could not load page after retries:", box_url, "\n")
    return(NULL)
  }

  
  # 🚨 Reject any page that is not a real box score
  if (length(html_nodes(pg, "div.scorebox")) == 0) {
    stop("❌ Not a real boxscore page (future or invalid): ", box_url)
  }
  
  # ---- 1. Extract Date Safely ----
  date_text <- pg %>% 
    html_node("div.scorebox_meta div") %>% 
    html_text(trim = TRUE)
  
  date_part <- str_extract(date_text, "[A-Za-z]+ \\d{1,2}, \\d{4}")
  game_date <- lubridate::mdy(date_part)
  
  if (is.na(game_date)) {
    stop("❌ COULD NOT PARSE DATE: ", box_url)
  }
  
  # ---- 2. Teams ----
  teams <- pg %>% html_nodes("div.scorebox strong a") %>% html_text()
  
  if (length(teams) < 2) {
    stop("❌ COULD NOT FIND TEAMS: ", box_url)
  }
  
  away_team <- teams[1]
  home_team <- teams[2]
  
  # ---- 3. Final Scores ----
  scores <- pg %>% html_nodes("div.scorebox div.scores div.score") %>% html_text()
  
  if (length(scores) < 2) {
    stop("❌ COULD NOT FIND SCORES: ", box_url)
  }
  
  away_score <- as.numeric(scores[1])
  home_score <- as.numeric(scores[2])
  
  # ---- 4. Fouls ----
  totals <- pg %>% html_nodes("tfoot tr")
  
  if (length(totals) < 2) {
    stop("❌ FOUL TOTALS NOT FOUND: ", box_url)
  }
  
  away_totals <- totals[[1]] %>% html_nodes("td") %>% html_text()
  home_totals <- totals[[2]] %>% html_nodes("td") %>% html_text()
  
  away_fouls <- as.numeric(away_totals[18])
  home_fouls <- as.numeric(home_totals[18])
  
  # ---- 5. Referees ----
  ref_nodes <- pg %>%
    html_nodes(xpath = "//div[strong[contains(., 'Officials')]]/a")
  
  if (length(ref_nodes) > 0) {
    refs <- ref_nodes %>% html_text(trim = TRUE)
  } else {
    refs <- character(0)
  }
  
  num_refs <- length(refs)
  
  

  # Store all referees (can be any number, not padded)
  
  # ---- Return tibble ----
  tibble(
    date = game_date,
    away_team,
    home_team,
    away_score,
    home_score,
    away_fouls,
    home_fouls,
    refs = list(refs),  # Store as list to handle variable number of refs
    num_refs = length(refs),
    url = box_url
  )
}

# ---------------------------------------------------------
# 3. SCRAPE DATE RANGE
# ---------------------------------------------------------
scrape_range <- function(start_date, end_date) {
  
  start_date <- as.Date(start_date, format = "%Y-%m-%d")
  end_date   <- as.Date(end_date, format = "%Y-%m-%d")
  
  dates <- seq.Date(start_date, end_date, by = "day")
  all_games <- tibble()
  
  for (i in seq_along(dates)) {
    d <- dates[i]
    
    cat("\n=== Scraping date:", as.character(d), "===\n")
    
    m  <- lubridate::month(d)
    dd <- lubridate::day(d)
    y  <- lubridate::year(d)
    
    links <- get_boxscore_links(m, dd, y)
    
    if (length(links) == 0) {
      cat("No games to scrape.\n")
      next
    }
    
    Sys.sleep(6 + runif(1, 0, 4))   # 6–10 seconds between each DATE PAGE
    
    for (link in links) {
      cat("   Scraping:", link, "\n")
      
      game_row <- try(scrape_game(link), silent = TRUE)
      
      if (inherits(game_row, "try-error") || is.null(game_row)) {
        cat("   ❌ ERROR scraping:", link, "\n")
        next
      }
      
      all_games <- bind_rows(all_games, game_row)
      Sys.sleep(8 + runif(1, 0, 4))   # wait 8–12 seconds PER GAME
    }
  }
  
  return(all_games)
}

# ---------------------------------------------------------
# 4. TEST FUNCTION - Test on a single game
# ---------------------------------------------------------
test_scraper <- function(test_url = NULL, test_date = "2023-10-24") {
  
  cat("🧪 Testing scraper...\n\n")
  
  # If no URL provided, get a game from the test date
  if (is.null(test_url)) {
    cat("Getting box score links for", test_date, "...\n")
    test_date_obj <- as.Date(test_date)
    links <- get_boxscore_links(
      lubridate::month(test_date_obj),
      lubridate::day(test_date_obj),
      lubridate::year(test_date_obj)
    )
    
    if (length(links) == 0) {
      cat("❌ No games found on", test_date, "\n")
      return(NULL)
    }
    
    test_url <- links[1]
    cat("Using first game:", test_url, "\n\n")
  }
  
  # Test scraping the game
  cat("Scraping game...\n")
  result <- try(scrape_game(test_url), silent = FALSE)
  
  if (inherits(result, "try-error")) {
    cat("\n❌ TEST FAILED:\n")
    cat(attr(result, "condition")$message, "\n")
    return(NULL)
  }
  
  cat("\n✅ TEST SUCCESSFUL!\n\n")
  cat("Extracted data:\n")
  print(result)
  cat("\nReferees found:", result$num_refs, "\n")
  if (result$num_refs > 0) {
    cat("Referee names:", paste(unlist(result$refs), collapse = ", "), "\n")
  }
  
  return(result)
}

# ---------------------------------------------------------
# 5. AUTOMATIC 30-DAY SCRAPE WINDOW
# ---------------------------------------------------------

start_date <- Sys.Date() - 7
end_date   <- Sys.Date() - 1

cat("Scraping window:", as.character(start_date), "to", as.character(end_date), "\n")

week_data <- scrape_range(start_date, end_date)

# Convert list of refs → comma-separated string
week_data_clean <- week_data %>%
  mutate(
    refs = sapply(refs, function(x) paste(unlist(x), collapse = ", ")),
    num_refs = lengths(strsplit(refs, ",\\s*"))
  )

write.csv(week_data_clean, "week_data_raw.csv", row.names = FALSE)

cat("Wrote week_data_raw.csv with", nrow(week_data_clean), "rows\n")

# make_plot.R

library(dplyr)
library(tidyr)
library(ggplot2)
library(stringr)
library(readr)

# Create plots folder if it doesn't exist
if (!dir.exists("plots")) {
  dir.create("plots")
}

# Load data
df <- read_csv("week_data_raw.csv")

# Clean & expand referees
df_heat <- df %>%
  mutate(
    refs = as.character(refs),
    refs = str_split(refs, ",\\s*")
  ) %>%
  unnest(refs) %>%
  mutate(refs = str_trim(refs, side = "both"))

# Compute foul differential
df_heat <- df_heat %>%
  mutate(foul_diff = home_fouls - away_fouls)

###############################################
### PLOT 1: BIAS BAR CHART (RED-BLUE GRADIENT)
###############################################

ref_agg <- df_heat %>%
  group_by(refs) %>%
  summarise(
    games = n(),
    avg_foul_diff = mean(foul_diff, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  filter(games >= 5) %>%
  arrange(desc(abs(avg_foul_diff))) %>%
  head(20)

p1 <- ggplot(ref_agg, aes(x = reorder(refs, avg_foul_diff), 
                          y = avg_foul_diff, 
                          fill = avg_foul_diff)) +
  geom_col(color = "black", linewidth = 0.3) +
  scale_fill_gradient2(
    low = "#2E86AB",
    mid = "#FFFFFF",
    high = "#EE4266",
    midpoint = 0,
    name = "Bias Direction"
  ) +
  coord_flip() +
  labs(
    title = "🏀 NBA Referee Home-Away Bias Tracker",
    subtitle = paste0("Top 20 Most Biased Referees (min. 5 games) • Updated ", format(Sys.Date(), "%B %d, %Y")),
    x = NULL,
    y = "Average Foul Differential (Home Fouls - Away Fouls)",
    caption = "Positive = More fouls on home team  |  Negative = More fouls on away team\nData: Basketball-Reference.com"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.background = element_rect(fill = "#F8F9FA", color = NA),
    panel.background = element_rect(fill = "#FFFFFF", color = NA),
    panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = "#E0E0E0", linewidth = 0.5),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 18, color = "#1A1A1A", hjust = 0),
    plot.subtitle = element_text(size = 11, color = "#666666", hjust = 0, margin = margin(b = 15)),
    plot.caption = element_text(size = 9, color = "#999999", hjust = 1, margin = margin(t = 15)),
    axis.text.y = element_text(size = 11, color = "#333333", face = "bold"),
    axis.text.x = element_text(size = 10, color = "#666666"),
    axis.title.x = element_text(size = 11, color = "#333333", margin = margin(t = 10)),
    legend.position = "top",
    legend.title = element_text(face = "bold", size = 11),
    legend.text = element_text(size = 9),
    legend.key.width = unit(2, "cm"),
    legend.key.height = unit(0.4, "cm"),
    plot.margin = margin(20, 20, 20, 20)
  ) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "#333333", linewidth = 0.8)

ggsave("plots/referee_bias_colorful.png", p1, width = 12, height = 10, dpi = 300, bg = "#F8F9FA")
cat("✅ Plot 1 saved: plots/referee_bias_colorful.png\n")

###############################################
### PLOT 2: SCATTER PLOT (HOME VS AWAY)
###############################################

ref_total_fouls <- df_heat %>%
  mutate(total_fouls = home_fouls + away_fouls) %>%
  group_by(refs) %>%
  summarise(
    games = n(),
    avg_total_fouls = mean(total_fouls, na.rm = TRUE),
    avg_home_fouls = mean(home_fouls, na.rm = TRUE),
    avg_away_fouls = mean(away_fouls, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  filter(games >= 5) %>%
  arrange(desc(avg_total_fouls)) %>%
  head(15)

p2 <- ggplot(ref_total_fouls, aes(x = avg_home_fouls, 
                                  y = avg_away_fouls, 
                                  size = games,
                                  color = avg_total_fouls)) +
  geom_point(alpha = 0.8) +
  scale_color_gradient(
    low = "#06D6A0",
    high = "#EF476F",
    name = "Avg Total\nFouls/Game"
  ) +
  scale_size_continuous(
    range = c(4, 15),
    name = "Games\nOfficiated"
  ) +
  geom_abline(intercept = 0, slope = 1, 
              linetype = "dashed", color = "#333333", linewidth = 0.8) +
  ggrepel::geom_text_repel(
    aes(label = refs),
    size = 3,
    color = "#1A1A1A",
    fontface = "bold",
    max.overlaps = 10,
    segment.color = "#999999",
    segment.size = 0.3
  ) +
  labs(
    title = "🔥 Referee Foul Distribution: Home vs Away",
    subtitle = paste0("Top 15 referees by total fouls called • Updated ", format(Sys.Date(), "%B %d, %Y")),
    x = "Average Home Team Fouls",
    y = "Average Away Team Fouls",
    caption = "Points above diagonal = more away fouls  |  Points below diagonal = more home fouls\nSize = number of games officiated"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.background = element_rect(fill = "#F8F9FA", color = NA),
    panel.background = element_rect(fill = "#FFFFFF", color = NA),
    panel.grid.major = element_line(color = "#E0E0E0", linewidth = 0.5),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 18, color = "#1A1A1A", hjust = 0),
    plot.subtitle = element_text(size = 11, color = "#666666", hjust = 0, margin = margin(b = 15)),
    plot.caption = element_text(size = 9, color = "#999999", hjust = 0, margin = margin(t = 15)),
    axis.text = element_text(size = 10, color = "#666666"),
    axis.title = element_text(size = 11, color = "#333333", face = "bold"),
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 10),
    legend.text = element_text(size = 9),
    plot.margin = margin(20, 20, 20, 20)
  )

ggsave("plots/referee_scatter.png", p2, width = 12, height = 9, dpi = 300, bg = "#F8F9FA")
cat("✅ Plot 2 saved: plots/referee_scatter.png\n")

###############################################
### PLOT 3: GROUPED BAR CHART (HOME VS AWAY)
###############################################

top_refs <- df_heat %>%
  group_by(refs) %>%
  summarise(games = n()) %>%
  filter(games >= 5) %>%
  arrange(desc(games)) %>%
  head(12) %>%
  pull(refs)

ref_metrics <- df_heat %>%
  filter(refs %in% top_refs) %>%
  mutate(foul_diff = home_fouls - away_fouls) %>%
  group_by(refs) %>%
  summarise(
    games = n(),
    avg_home_fouls = mean(home_fouls, na.rm = TRUE),
    avg_away_fouls = mean(away_fouls, na.rm = TRUE),
    foul_diff = mean(foul_diff, na.rm = TRUE)
  ) %>%
  ungroup()

ref_long <- ref_metrics %>%
  select(refs, avg_home_fouls, avg_away_fouls) %>%
  pivot_longer(cols = c(avg_home_fouls, avg_away_fouls),
               names_to = "type",
               values_to = "fouls") %>%
  mutate(
    type = ifelse(type == "avg_home_fouls", "Home Team", "Away Team")
  )

p3 <- ggplot(ref_long, aes(x = reorder(refs, fouls), y = fouls, fill = type)) +
  geom_col(position = "dodge", color = "black", linewidth = 0.3) +
  scale_fill_manual(
    values = c("Home Team" = "#FF6B35", "Away Team" = "#004E89"),
    name = "Team Type"
  ) +
  coord_flip() +
  labs(
    title = "🏠 Home vs Away Foul Rates by Referee",
    subtitle = paste0("Top 12 most active referees (5+ games) • Updated ", format(Sys.Date(), "%B %d, %Y")),
    x = NULL,
    y = "Average Fouls Per Game",
    caption = "Larger gap between bars = stronger home/away bias\nData: Basketball-Reference.com"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.background = element_rect(fill = "#F8F9FA", color = NA),
    panel.background = element_rect(fill = "#FFFFFF", color = NA),
    panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = "#E0E0E0", linewidth = 0.5),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 18, color = "#1A1A1A", hjust = 0),
    plot.subtitle = element_text(size = 11, color = "#666666", hjust = 0, margin = margin(b = 15)),
    plot.caption = element_text(size = 9, color = "#999999", hjust = 0, margin = margin(t = 15)),
    axis.text.y = element_text(size = 11, color = "#333333", face = "bold"),
    axis.text.x = element_text(size = 10, color = "#666666"),
    axis.title.x = element_text(size = 11, color = "#333333", margin = margin(t = 10)),
    legend.position = "top",
    legend.title = element_text(face = "bold", size = 11),
    legend.text = element_text(size = 10),
    legend.key.size = unit(0.8, "cm"),
    plot.margin = margin(20, 20, 20, 20)
  )

ggsave("plots/referee_home_away_bars.png", p3, width = 12, height = 9, dpi = 300, bg = "#F8F9FA")
cat("✅ Plot 3 saved: plots/referee_home_away_bars.png\n")

###############################################
### SUMMARY
###############################################

cat("\n🎨 ==========================================\n")
cat("   ALL 3 PLOTS CREATED SUCCESSFULLY!\n")
cat("==========================================\n")
cat("📊 Total referee assignments analyzed:", nrow(df_heat), "\n")
cat("👨‍⚖️ Unique referees found:", n_distinct(df_heat$refs), "\n")
cat("🏀 Games in dataset:", nrow(df), "\n")
cat("\n📁 Saved to plots/ folder:\n")
cat("   1. referee_bias_colorful.png (bias bar chart)\n")
cat("   2. referee_scatter.png (home vs away scatter)\n")
cat("   3. referee_home_away_bars.png (grouped bars)\n")
cat("==========================================\n")


# Data Breach Disclosures and Firm Financial Outcomes (Phase 2)
# For a knit-ready report with TOC and formatted output, use Data_Breaches.Rmd
# and knit to HTML (or PDF/Word) from RStudio.

# =============================================================================
# SETUP
# =============================================================================
# Set working directory so relative paths (e.g. CSV file) resolve correctly.
# Adjust the path below if you run the script from a different project location.
setwd("/Users/arnavsahai/Desktop/Data Analysis for Policy Research using R/Project")

# Load packages: tidyverse (data manipulation, plotting), tidyquant (stock data),
# lubridate (dates), ggplot2 (graphs). Uncomment next line to install tidyquant.
#install.packages("tidyquant")
library(tidyverse)
library(tidyquant)
library(lubridate)
library(ggplot2)


# =============================================================================
# LOAD AND CLEAN BREACH DATA
# =============================================================================
# Source: Rosati & Lynn (2020), Mendeley Data. Contains breach events for
# NYSE/NASDAQ firms (2005–2015). We parse event_date, keep standard breach
# types (HACK, INSD, PORT, etc.), add readable labels, coerce breach_size to
# numeric, and drop rows with missing ticker or event_date. confound_dum
# flags events with another major announcement within 10 days (excluded from
# main analysis).
breaches_raw <- read_csv("Data Breach Dataset.csv", show_col_types = FALSE)
breaches <- breaches_raw %>%
  mutate(event_date = dmy(event_date)) %>%
  filter(breach_type %in% c("HACK", "INSD", "PORT",
                            "DISC", "CARD", "PHYS",
                            "STAT", "UNKN")) %>%
  mutate(breach_type_label = case_when(
    breach_type == "HACK" ~ "Hacking",
    breach_type == "INSD" ~ "Insider",
    breach_type == "PORT" ~ "Portable Device",
    breach_type == "DISC" ~ "Unintended Disclosure",
    breach_type == "CARD" ~ "Card Fraud",
    breach_type == "PHYS" ~ "Physical Loss",
    breach_type == "STAT" ~ "Stationary Device",
    breach_type == "UNKN" ~ "Unknown"
  )) %>%
  mutate(breach_size = as.numeric(breach_size)) %>%
  filter(!is.na(ticker), !is.na(event_date)) %>%
  select(Event_ID, ticker, name, event_date, event_year,
         breach_type, breach_type_label, breach_size,
         confound_dum, confound_type, hq_state)

# =============================================================================
# MARKET RETURNS (S&P 500)
# =============================================================================
# We need a market benchmark to compute "normal" expected returns for each
# firm (market model). We pull S&P 500 (^GSPC) daily prices from Yahoo Finance
# via tidyquant, then convert to daily log returns. These are merged with each
# firm's returns to estimate alpha and beta and to define abnormal returns.
sp500_prices <- tq_get("^GSPC", get = "stock.prices",
                       from = "2003-01-01", to = "2016-01-01")

sp500_ret <- sp500_prices %>%
  tq_transmute(select = adjusted, mutate_fun = periodReturn,
               period = "daily", type = "log", col_rename = "mkt_ret") %>%
  mutate(date = as.Date(date))


# =============================================================================
# FIRM-LEVEL EVENT STUDY: FETCH PRICES AND COMPUTE ABNORMAL RETURNS
# =============================================================================
# For each breach event we: (1) fetch the firm's daily stock prices around the
# event date, (2) compute daily log returns and merge with S&P 500 returns,
# (3) define event time t = 0 as the disclosure date, (4) use days -200 to -11
# as the estimation window to fit the market model (expected return = alpha +
# beta * mkt_ret), (5) compute abnormal return (AR) = actual return - expected
# return and cumulative AR (CAR) in the event window (-5 to +10). Events with
# too few trading days in the estimation window or failed data are skipped.
# Sys.sleep(0.3) throttles requests to avoid overloading the data source.
results <- list()

for (i in 1:nrow(breaches)) {
  
  ticker_i   <- breaches$ticker[i]
  event_date <- breaches$event_date[i]
  
  # Progress: show when knitting only every 50 events to avoid flooding output
  if (!isTRUE(getOption("knitr.in.progress"))) {
    cat(sprintf("[%d/%d] %s — %s\n", i, nrow(breaches), ticker_i, event_date))
  } else if (i %% 50 == 0) {
    message("Processing event ", i, " of ", nrow(breaches))
  }
  
  # Fetch daily stock prices; on failure (e.g. delisted ticker) skip.
  prices <- tryCatch({
    tq_get(ticker_i, get = "stock.prices",
           from = event_date - 300,
           to   = event_date + 45)
  }, error = function(e) NULL)
  
  if (!is.data.frame(prices) || nrow(prices) < 1) next
  
  # Daily log return = log(close_t / close_{t-1}). Use adjusted close for splits/dividends.
  firm_ret <- prices %>%
    tq_transmute(select = adjusted, mutate_fun = periodReturn,
                 period = "daily", type = "log", col_rename = "firm_ret") %>%
    mutate(date = as.Date(date))
  
  # Align firm and market returns by date; t = 0 is the event date (disclosure).
  merged <- firm_ret %>%
    inner_join(sp500_ret, by = "date") %>%
    arrange(date) %>%
    mutate(t = row_number() - which.min(abs(as.numeric(date - event_date))))
  
  # Estimation window: days -200 to -11 relative to disclosure. Need enough
  # observations to estimate market model; skip if fewer than 60 trading days.
  est_window <- merged %>% filter(t >= -200, t <= -11)
  
  if (nrow(est_window) < 60) next
  
  # Market model: E[R_i] = alpha + beta * R_m. OLS gives alpha_hat, beta_hat.
  ols <- lm(firm_ret ~ mkt_ret, data = est_window)
  alpha_hat <- coef(ols)[1]
  beta_hat <- coef(ols)[2]
  
  # Event window: t in [-5, +10]. AR = actual return - expected; CAR = cumsum(AR).
  # car_0_10 is cumsum of AR from t=0 onward only, so at t=10 it equals CAR(0,+10).
  ev_window <- merged %>%
    filter(t >= -5, t <= 10) %>%
    mutate(
      expected_ret = alpha_hat + beta_hat * mkt_ret,
      ar           = firm_ret - expected_ret,
      car          = cumsum(ar),
      car_0_10     = cumsum(if_else(t >= 0, ar, 0)),  # CAR(0,+10) at t=10
      ticker       = ticker_i,
      event_date   = event_date,
      Event_ID     = breaches$Event_ID[i]
    )
  
  results[[i]] <- ev_window
  Sys.sleep(0.3)
}

# Stack all event windows into one panel (one row per event-day).
stock_panel <- bind_rows(results)

# =============================================================================
# PANEL VARIABLES FOR TWFE (TWO-WAY FIXED EFFECTS)
# =============================================================================
# For the Phase 2 empirical strategy we build a firm-day panel. Post_it = 1
# for all days on or after disclosure (t >= 0); days_since_disclosure = t.
# This supports regressions: Return_it = α_i + λ_t + β·Post_it + ε_it (baseline),
# or dynamic specifications with leads/lags, and heterogeneity (e.g. interaction
# with log(breach_size) or breach type). Here we only add the indicators; the
# actual TWFE estimation can be done with fixest or lm with factor().
stock_panel <- stock_panel %>%
  mutate(Post_it = as.integer(t >= 0),
         days_since_disclosure = t)

# How many distinct breach events made it into the panel (some tickers fail
# to load or have insufficient history).
n_distinct(stock_panel$Event_ID)

# List events that were skipped (e.g. delisted or renamed tickers). Useful
# for reporting limitations. Use kable() when knitting for nicer tables.
missing <- breaches %>%
  filter(!Event_ID %in% stock_panel$Event_ID) %>%
  select(Event_ID, ticker, name, event_date)
if (requireNamespace("knitr", quietly = TRUE)) {
  knitr::kable(head(missing, 15), caption = "Sample of skipped events")
} else {
  print(missing)
}

# Note: many skipped tickers are delisted or renamed (e.g. AMR, Kodak). This
# is a known limitation to mention in the paper.
# quick look at the data
#view(stock_panel)


# =============================================================================
# MERGE BREACH CHARACTERISTICS INTO STOCK PANEL
# =============================================================================
# Attach breach_type, breach_type_label, breach_size, confound_dum, and hq_state
# to each row of stock_panel so we can subset by type/size and control for
# confounded events in analysis and graphs.
stock_panel <- stock_panel %>%
  left_join(breaches %>% select(Event_ID, breach_type, breach_type_label,
                                breach_size, confound_dum, hq_state, event_year),
            by = "Event_ID")

# verify merge worked
#view(stock_panel)


# =============================================================================
# APPENDIX GRAPH 1: TOP 10 WORST STOCK PERFORMERS AFTER BREACH
# =============================================================================
# Among non-confounded events, we rank by CAR(0,+10) (cumulative abnormal
# return from disclosure through day +10) and take the 10 most negative. We
# then plot each of these events' CAR path over t = -5 to +10 so the reader
# can see the trajectory of losses. Facets show one firm per panel.
top10_worst <- stock_panel %>%
  filter(t == 10, confound_dum == 0) %>%
  arrange(car_0_10) %>%
  slice_head(n = 10) %>%
  select(Event_ID, ticker, event_date, car_0_10) %>%
  mutate(label = paste0(ticker, "\n", format(event_date, "%b %Y")))

panel_data_worst <- stock_panel %>%
  filter(Event_ID %in% top10_worst$Event_ID) %>%
  left_join(top10_worst %>% select(Event_ID, label), by = "Event_ID")

ggplot(panel_data_worst, aes(x = t, y = car)) +
  geom_line(color = "#E63946", linewidth = 1) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black", linewidth = 0.5) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
  geom_ribbon(aes(ymin = car, ymax = 0), fill = "#E63946", alpha = 0.15) +
  facet_wrap(~ label, ncol = 5) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  labs(title = "Top 10 Worst Stock Performers After Data Breach Disclosure",
       subtitle = "Ranked by CAR(0, +10) | Confounded events excluded",
       x = "Trading Days Relative to Disclosure",
       y = "Cumulative Abnormal Return") +
  theme_minimal() +
  theme(strip.text = element_text(face = "bold", size = 9),
        panel.grid.minor = element_blank())

# =============================================================================
# APPENDIX GRAPH 2: MEAN CAR(0,+10) BY BREACH TYPE
# =============================================================================
# We compare average 10-day cumulative abnormal returns across four common
# breach types (Hacking, Insider, Portable Device, Unintended Disclosure).
# Confounded events are excluded. This addresses whether the market penalty
# varies by how the breach occurred; the Phase 2 doc notes ~4% worse returns
# for larger breaches. The exists() check lets you re-run this graph chunk
# without re-running the full script.
four_types <- c("Hacking", "Insider", "Portable Device", "Unintended Disclosure")
if (!exists("car10_by_type")) {
  car10_by_type <- stock_panel %>%
    filter(t == 10, confound_dum == 0, breach_type_label %in% four_types) %>%
    group_by(breach_type_label) %>%
    summarise(
      n = n(),
      mean_car = mean(car_0_10, na.rm = TRUE),
      median_car = median(car_0_10, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(breach_type_label = fct_reorder(breach_type_label, mean_car))
}
ggplot(car10_by_type, aes(x = breach_type_label, y = mean_car, fill = mean_car < 0)) +
  geom_col(show.legend = FALSE) +
  geom_hline(yintercept = 0, color = "grey40", linewidth = 0.4) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_fill_manual(values = c("TRUE" = "#E63946", "FALSE" = "#2A9D8F")) +
  coord_flip() +
  labs(
    title = "Average 10-Day Cumulative Abnormal Return by Breach Type",
    subtitle = "CAR(0, +10) | Confounded events excluded | Four common breach types",
    x = NULL,
    y = "Mean CAR(0, +10)"
  ) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank())


# =============================================================================
# ADDITIONAL DATA ANALYSIS (Phase 2: EDA, event-study summary, heterogeneity)
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Summary statistics (breach characteristics)
# -----------------------------------------------------------------------------
# Overall counts and breach-size stats for the cleaned breach sample. We also
# tabulate events by year (to see time trends) and by breach type (to see
# which categories are most common). confound_dum tells us how many events
# are flagged as having a concurrent major announcement.
breach_summary <- breaches %>%
  summarise(
    n_events = n(),
    n_confounded = sum(confound_dum == 1, na.rm = TRUE),
    pct_confounded = 100 * mean(confound_dum, na.rm = TRUE),
    breach_size_median = median(breach_size, na.rm = TRUE),
    breach_size_mean = mean(breach_size, na.rm = TRUE),
    breach_size_sd = sd(breach_size, na.rm = TRUE),
    .groups = "drop"
  )
if (requireNamespace("knitr", quietly = TRUE)) {
  knitr::kable(breach_summary, digits = 2, caption = "Breach sample summary")
} else {
  print(breach_summary)
}

events_by_year <- breaches %>%
  count(event_year, name = "n_events") %>%
  arrange(event_year)
if (requireNamespace("knitr", quietly = TRUE)) {
  knitr::kable(events_by_year, caption = "Events by year")
} else {
  print(events_by_year)
}

events_by_type <- breaches %>%
  count(breach_type_label, name = "n_events") %>%
  arrange(desc(n_events))
if (requireNamespace("knitr", quietly = TRUE)) {
  knitr::kable(events_by_type, caption = "Events by breach type")
} else {
  print(events_by_type)
}

# -----------------------------------------------------------------------------
# 2. Average abnormal return path (event-study style)
# -----------------------------------------------------------------------------
# For each event day t we compute the mean AR and mean CAR across all
# non-confounded events. The first plot shows daily abnormal returns (bars);
# the second shows the cumulative path. This is the standard "event study"
# visualization: we expect AR to spike around t = 0 if the market reacts to
# disclosure, and CAR to drift down (or up) after the event.
ar_by_t <- stock_panel %>%
  filter(confound_dum == 0) %>%
  group_by(t) %>%
  summarise(
    mean_ar = mean(ar, na.rm = TRUE),
    mean_car = mean(car, na.rm = TRUE),
    n = n(),
    .groups = "drop"
  )

ggplot(ar_by_t, aes(x = t, y = mean_ar)) +
  geom_col(fill = "steelblue", alpha = 0.8) +
  geom_hline(yintercept = 0, color = "grey40", linewidth = 0.4) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "black") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.01)) +
  labs(
    title = "Average Abnormal Return by Event Day",
    subtitle = "Non-confounded events only | Disclosure at t = 0",
    x = "Trading days relative to disclosure",
    y = "Mean abnormal return"
  ) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank())

ggplot(ar_by_t, aes(x = t, y = mean_car)) +
  geom_line(color = "darkred", linewidth = 1) +
  geom_point(color = "darkred", size = 2) +
  geom_hline(yintercept = 0, color = "grey40", linewidth = 0.4) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "black") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  labs(
    title = "Average Cumulative Abnormal Return by Event Day",
    subtitle = "Non-confounded events only | Disclosure at t = 0",
    x = "Trading days relative to disclosure",
    y = "Mean CAR"
  ) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank())

# -----------------------------------------------------------------------------
# 3. Cross-sectional analysis: CAR(0,+10) vs breach size and type
# -----------------------------------------------------------------------------
# We collapse to one row per event (at t = 10) and build log_breach_size =
# log(1 + breach_size) to handle zeros/missing. We summarize the distribution
# of CAR(0,+10), then run OLS: (i) CAR on log breach size and breach type
# dummies, (ii) CAR on breach type only. This tests whether larger breaches
# or certain types are associated with more negative returns.
car_cross <- stock_panel %>%
  filter(t == 10, confound_dum == 0) %>%
  select(Event_ID, ticker, car_0_10, breach_size, breach_type, breach_type_label, event_year) %>%
  distinct() %>%
  mutate(log_breach_size = log(1 + breach_size))

car_summary <- car_cross %>%
  summarise(
    n = n(),
    mean_car = mean(car_0_10, na.rm = TRUE),
    median_car = median(car_0_10, na.rm = TRUE),
    sd_car = sd(car_0_10, na.rm = TRUE),
    min_car = min(car_0_10, na.rm = TRUE),
    max_car = max(car_0_10, na.rm = TRUE)
  )
if (requireNamespace("knitr", quietly = TRUE)) {
  knitr::kable(car_summary, digits = 4, caption = "CAR(0,+10) summary (non-confounded)")
} else {
  print(car_summary)
}

lm_car_size_type <- lm(car_0_10 ~ log_breach_size + factor(breach_type), data = car_cross)
summary(lm_car_size_type)

lm_car_type <- lm(car_0_10 ~ factor(breach_type), data = car_cross)
summary(lm_car_type)

# -----------------------------------------------------------------------------
# 4. Heterogeneity: mean CAR(0,+10) by breach size bins
# -----------------------------------------------------------------------------
# We bin breach size (records exposed) into categories: Missing/0, <1k,
# 1k–10k, 10k–100k, 100k+. Then we compute mean CAR(0,+10) within each bin
# and plot. This shows whether the market penalty is stronger for larger
# breaches without imposing a linear log-size effect.
car_cross_bins <- car_cross %>%
  mutate(
    size_bin = case_when(
      is.na(breach_size) | breach_size == 0 ~ "Missing/0",
      breach_size < 1000 ~ "<1k",
      breach_size < 10000 ~ "1k–10k",
      breach_size < 100000 ~ "10k–100k",
      TRUE ~ "100k+"
    ),
    size_bin = factor(size_bin, levels = c("Missing/0", "<1k", "1k–10k", "10k–100k", "100k+"))
  ) %>%
  group_by(size_bin) %>%
  summarise(n = n(), mean_car = mean(car_0_10, na.rm = TRUE), .groups = "drop")

ggplot(car_cross_bins, aes(x = size_bin, y = mean_car, fill = mean_car < 0)) +
  geom_col(show.legend = FALSE) +
  geom_hline(yintercept = 0, color = "grey40", linewidth = 0.4) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_fill_manual(values = c("TRUE" = "#E63946", "FALSE" = "#2A9D8F")) +
  labs(
    title = "Average CAR(0,+10) by Breach Size (records exposed)",
    subtitle = "Non-confounded events only",
    x = "Breach size", y = "Mean CAR(0,+10)"
  ) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank(), axis.text.x = element_text(angle = 30, hjust = 1))

# -----------------------------------------------------------------------------
# 5. EDA: Events over time and breach size distribution
# -----------------------------------------------------------------------------
# Left: bar chart of number of breach disclosures per year (2005–2015). Right:
# histogram of breach size (records exposed) for events with non-missing,
# positive size. These help describe the sample and show right-skew in
# breach size noted in the Phase 2 document.
ggplot(events_by_year, aes(x = event_year, y = n_events)) +
  geom_col(fill = "steelblue", alpha = 0.8) +
  labs(
    title = "Data breach disclosures by year",
    subtitle = "Sample: NYSE/NASDAQ firms, 2005–2015",
    x = "Year", y = "Number of events"
  ) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank())

ggplot(breaches %>% filter(!is.na(breach_size), breach_size > 0), aes(x = breach_size / 1000)) +
  geom_histogram(bins = 40, fill = "steelblue", alpha = 0.8, boundary = 0) +
  scale_x_continuous(labels = function(x) paste0(x, "k")) +
  labs(
    title = "Distribution of breach size (records exposed)",
    subtitle = "Excluding missing and zero",
    x = "Breach size (thousands of records)", y = "Count"
  ) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank())

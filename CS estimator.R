#Version 1 CA Estimator. 
# Strategy: collapse every breach into event time [t-18, t+18], then use the
# S&P 500 index over the SAME calendar window as a synthetic never-treated
# unit for each breach. Outcome = cumulative return from start of window, so
# CS dynamic ATTs read as cumulative abnormal returns (CARs) relative to t-1.
# =============================================================================

#  setup
library(tidyverse)
library(tidyquant)
library(lubridate)
library(did)

set.seed(42)

# Adjust path/filename to match what's on your disk
breaches_raw <- read_csv("Data Breach Dataset.csv", show_col_types = FALSE)

# cleaning the beaches dataset
breaches <- breaches_raw %>%
  mutate(event_date = dmy(event_date)) %>%
  filter(breach_type %in% c("INSD","PORT","DISC","CARD","STAT","UNKN"),
         confound_dum == 0,
         !is.na(ticker), !is.na(event_date)) %>%
  distinct(Event_ID, .keep_all = TRUE)

cat("Clean breach events:", nrow(breaches), "\n") #153 Cleaned breach events. 

# Pulling returns from the market for the breach events
window_pad <- 25  # calendar-day pad around a larger window just to see what happens.
date_min <- min(breaches$event_date) - window_pad
date_max <- max(breaches$event_date) + window_pad

#Pulling S and P 500 from around that time, this should be our "never treated" 
#As the index should not change or be impacted by isolated cyber events
#this as a control should also control for news noise in the data (good market days, etc.)
sp500 <- tq_get("^GSPC", from = date_min, to = date_max, get = "stock.prices") %>%
  tq_transmute(select = adjusted, mutate_fun = periodReturn,
               period = "daily", col_rename = "ret_mkt") %>%
  rename(trade_date = date)


#Pulling firm returns.
tickers <- unique(breaches$ticker)
firm_prices <- tq_get(tickers, from = date_min, to = date_max, get = "stock.prices")
firm_rets <- firm_prices %>%
  group_by(symbol) %>%
  tq_transmute(select = adjusted, mutate_fun = periodReturn,
               period = "daily", col_rename = "ret_firm") %>%
  ungroup() %>%
  rename(ticker = symbol, trade_date = date)

# Event-times function to speed up the process
build_event_window <- function(ev_id, tkr, ev_date) {
  # Firm side retrns
  f <- firm_rets %>%
    filter(ticker == tkr,
           trade_date >= ev_date - window_pad,
           trade_date <= ev_date + window_pad) %>%
    arrange(trade_date)
  if (nrow(f) == 0) return(NULL)
  # First trading day on/after the event date = event time 0
  t0_idx <- which(f$trade_date >= ev_date)[1]
  if (is.na(t0_idx)) return(NULL)
  f <- f %>%
    mutate(event_time = row_number() - t0_idx) %>%
    filter(event_time >= -15, event_time <= 15)
  if (nrow(f) < 25) return(NULL)
  # Cumulative firm return from start of window 
  f <- f %>% mutate(cum_ret = cumsum(ret_firm))
  # control/nevertakers/SandP over the same calendar window, then cumulative
  m <- sp500 %>%
    filter(trade_date >= min(f$trade_date),
           trade_date <= max(f$trade_date)) %>%
    arrange(trade_date) %>%
    left_join(f %>% select(trade_date, event_time), by = "trade_date") %>%
    filter(!is.na(event_time)) %>%
    mutate(cum_ret = cumsum(ret_mkt))
  
  treated <- tibble(
    Event_ID = ev_id,
    unit_id = paste0("F_", ev_id),
    event_time = f$event_time,
    y = f$cum_ret,
    treat = 1L)
  control <- tibble(
    Event_ID = ev_id,
    unit_id = paste0("M_", ev_id),
    event_time = m$event_time,
    y = m$cum_ret,
    treat = 0L)
  bind_rows(treated, control)
}



#used pmap_dfr to bind efficiently
panel <- breaches %>%
  select(Event_ID, ticker, event_date) %>%
  pmap_dfr(~ build_event_window(..1, ..2, ..3))


# Shift event_time to strictly positive periods
# Treatment turns on at event_time = 0 -> period = 16, so G = 16 for treated.
# Never-treated units get G = 0. 
panel <- panel %>%
  mutate(period = as.integer(event_time + 15),
         G      = ifelse(treat == 1L, 15, 0),
         id_num = as.integer(factor(paste(unit_id, Event_ID, sep = "_")))) %>%
  filter(!is.na(y), is.finite(y), !is.na(G), !is.na(period))

panel <- panel %>%
  left_join(breaches %>% select(Event_ID, breach_size), by = "Event_ID") %>%
  mutate(w = if_else(treat == 1L, log(breach_size + 1), 1))



# Sanity checks
cat("Never-treated rows:", sum(panel$G == 0),
    "| Treated rows:", sum(panel$G == 16), "\n")
cat("Unique ids:", n_distinct(panel$id_num), "\n")

# The Preliminary CS estimaror, (no covars, but with weights.)
att <- att_gt(yname = "y", 
              tname = "period",
              idname = "id_num",
              gname = "G",
# note: weights by log of breach size (has a +1 incase some are reportd zero)
              weightsname = "w",
              data = panel,
              control_group = "nevertreated",
# also had to make this false because repeated cross sections.
              panel = FALSE, 
              bstrap = TRUE,
              cband = TRUE,
              est_method = "dr")

summary(att)

# create the ATT (aggregating results of the event study with a 15 day window)
es <- aggte(att, type = "dynamic", min_e = -15, max_e = 15, na.rm = TRUE)
summary(es)


#plotting the event study
es_df <- tibble(event_time = es$egt,
                att = es$att.egt,
                se = es$se.egt) %>%
  mutate(lo = att - 1.96 * se, hi = att + 1.96 * se)

p <- ggplot(es_df, aes(event_time, att)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_vline(xintercept = 0, linetype = "dotted", color = "grey40") +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.2, fill = "steelblue") +
  geom_line(color = "steelblue", linewidth = 0.8) +
  geom_point(color = "steelblue") +
  labs(title = "CS Dynamic ATT: Cumulative Abnoral Returns Afer Breach Dislosure",
       subtitle = "S&P 500 as synthetic never-treated control",
       x = "Event time (trading days, 0 = breach disclosure)",
       y = "Cumulative ATT (CAR)") +
  theme_minimal(base_size = 12)

p

# V2 with weights, increasing normalization, and including covariates. 
# Data Breach Disclosures using Callaway-Sant'Anna (CS) Estimator
# Final specs:
#   - Cumulative-return outcome (in short: CAR)
#   - The never-treated arm whikch is synthetic = S&P 500 over the same calendar window
#   - Doubly-robust estimation with three covariates:
#       (1) pre-event "volatility", (2) pre-event "momentum", (3) log size on day -1
#   - Normalized log(breach_size) weights so no single mega-event dominates (since there is high variability in size of breaches)

# clean environment so no leftover columns from prio
# runs interfere with the left_join below.
rm(list = ls())

# Setup (again)
library(tidyverse)
library(tidyquant)
library(lubridate)
library(did)

set.seed(42)

# reading data again
breaches_raw <- read_csv("Data Breach Dataset.csv", show_col_types = FALSE)

# Same datacleaning proceedure
breaches <- breaches_raw %>%
  mutate(event_date = dmy(event_date)) %>%
  filter(breach_type %in% c("INSD","PORT","DISC","CARD","STAT","UNKN"),
                confound_dum == 0,
                !is.na(ticker), !is.na(event_date),confound_dum == 0,
         !is.na(ticker), !is.na(event_date)) %>%
  distinct(Event_ID, .keep_all = TRUE)

#ensure this is the same as the previous CS estimator before moving on
cat("Clean breach events:", nrow(breaches), "\n")

# Firm and market prices pulling for "returns" to be used fro cumilative return
# taking a larger window pre-event (just to examine if there is variation before)


# pre-event estimation window.
hist_pad   <- 400
window_pad <- 25
date_min <- min(breaches$event_date) - hist_pad
date_max <- max(breaches$event_date) + window_pad

#pulling prices from SandP 500 to use for CAR (cum abnormal retrn)
sp500_px <- tq_get("^GSPC", from = date_min, to = date_max, get = "stock.prices") %>%
  select(trade_date = date, adjusted) %>%
  arrange(trade_date)

#chanfing retuns to market retuns.
sp500 <- sp500_px %>%
  mutate(ret_mkt = adjusted / lag(adjusted) - 1) %>%
  filter(!is.na(ret_mkt))

#different tickers
tickers <- unique(breaches$ticker)
cat("Pulling firm prices for", length(tickers), "tickers...\n")

firm_px <- tq_get(tickers, from = date_min, to = date_max, get = "stock.prices") %>%
  select(ticker = symbol, trade_date = date, adjusted, volume)

#firm returns
firm_rets <- firm_px %>%
  group_by(ticker) %>%
  arrange(trade_date, .by_group = TRUE) %>%
  mutate(ret_firm = adjusted / lag(adjusted) - 1) %>%
  ungroup() %>%
  filter(!is.na(ret_firm))

# Addition: Adding covariates from yahoo data on unique event IDs
# Pre-event volatility, momentum, and log size on day -1, computed over the
# [-250, -30] trading-day window before each event date.
compute_covars_firm <- function(tkr, ev_date) {
  s <- firm_rets %>% filter(ticker == tkr, trade_date < ev_date) %>%
    arrange(trade_date)
  if (nrow(s) < 60) return(tibble(pre_vol = NA, pre_mom = NA, log_size = NA))
  est <- s %>% slice_tail(n = 250) %>% slice_head(n = 220)
  if (nrow(est) < 60) return(tibble(pre_vol = NA, pre_mom = NA, log_size = NA))
  last_row <- s %>% slice_tail(n = 1)
  tibble(pre_vol  = sd(est$ret_firm, na.rm = TRUE),
         pre_mom  = sum(est$ret_firm, na.rm = TRUE),
         log_size = log(last_row$adjusted))
}



compute_covars_mkt <- function(ev_date) {
  s <- sp500 %>% filter(trade_date < ev_date) %>% arrange(trade_date)
  if (nrow(s) < 60) return(tibble(pre_vol = NA, pre_mom = NA, log_size = NA))
  est <- s %>% slice_tail(n = 250) %>% slice_head(n = 220)
  last_row <- s %>% slice_tail(n = 1)
  tibble(pre_vol  = sd(est$ret_mkt, na.rm = TRUE),
         pre_mom  = sum(est$ret_mkt, na.rm = TRUE),
         log_size = log(last_row$adjusted))
}

# again creating the event window
build_event_window <- function(ev_id, tkr, ev_date) {
  f <- firm_rets %>%
    filter(ticker == tkr,
           trade_date >= ev_date - window_pad,
           trade_date <= ev_date + window_pad) %>%
    arrange(trade_date)
  if (nrow(f) == 0) return(NULL)
  
  t0_idx <- which(f$trade_date >= ev_date)[1]
  if (is.na(t0_idx)) return(NULL)
  f <- f %>%
    mutate(event_time = row_number() - t0_idx) %>%
    filter(event_time >= -20, event_time <= 20)
  if (nrow(f) < 25) return(NULL)
  f <- f %>% mutate(cum_ret = cumsum(ret_firm))
  
  m <- sp500 %>%
    filter(trade_date >= min(f$trade_date),
           trade_date <= max(f$trade_date)) %>%
    arrange(trade_date) %>%
    left_join(f %>% select(trade_date, event_time), by = "trade_date") %>%
    filter(!is.na(event_time)) %>%
    mutate(cum_ret = cumsum(ret_mkt))
  
  cv_f <- compute_covars_firm(tkr, ev_date)
  cv_m <- compute_covars_mkt(ev_date)
  if (any(is.na(cv_f)) || any(is.na(cv_m))) return(NULL)
  
  treated <- tibble(
    Event_ID = ev_id, unit_id = paste0("F_", ev_id),
    event_time = f$event_time, y = f$cum_ret, treat = 1L,
    pre_vol = cv_f$pre_vol, pre_mom = cv_f$pre_mom, log_size = cv_f$log_size)
  control <- tibble(
    Event_ID = ev_id, unit_id = paste0("M_", ev_id),
    event_time = m$event_time, y = m$cum_ret, treat = 0L,
    pre_vol = cv_m$pre_vol, pre_mom = cv_m$pre_mom, log_size = cv_m$log_size)
  bind_rows(treated, control)
}

panel <- breaches %>%
  select(Event_ID, ticker, event_date) %>%
  pmap_dfr(~ build_event_window(..1, ..2, ..3))

# attaching weights but also combinding panel (main data source for CS estimnator)
# Normalized log breach-size weights: keeps the relative ordering (bigger
# breaches still count more) but rescales so the mean treated weight = 1,
# preventing a few mega-breaches from dominating the variance basicallt
panel <- panel %>%
  left_join(breaches %>% select(Event_ID, breach_size), by = "Event_ID") %>%
  mutate(period  = as.integer(event_time + 16),
         G       = ifelse(treat == 1L, 16, 0),
         id_num  = as.integer(factor(paste(unit_id, Event_ID, sep = "_"))),
         w_raw   = log(pmax(breach_size, 1) + 1),
         w       = w_raw / mean(w_raw[treat == 1L], na.rm = TRUE)) %>%
  filter(!is.na(y), is.finite(y), !is.na(G), !is.na(period),
         !is.na(w), is.finite(w),
        !is.na(pre_mom), !is.na(log_size))

#again a gut/sanity check
cat("Never-treated rows:", sum(panel$G == 0),
    "| Treated rows:", sum(panel$G == 16), "\n")
cat("Unique ids:", n_distinct(panel$id_num), "\n")

# CS estimator w/covariates, weights and bootstrap to normalize removed volume? niot sure its a good covariate.
att <- att_gt(yname = "y",
              tname = "period",
              idname = "id_num",
              gname = "G",
              xformla = ~  pre_mom + log_size,
              data = panel,
              control_group = "nevertreated",
              weightsname = "w",
              panel = FALSE,
              bstrap = TRUE,
              biters = 1000,
              cband = TRUE,
              est_method = "dr")

summary(att)

es <- aggte(att, type = "dynamic", min_e = -15, max_e = 18, na.rm = TRUE)
summary(es)

# Plot
es_df <- tibble(event_time = es$egt, att = es$att.egt, se = es$se.egt) %>%
  mutate(lo = att - 1.96 * se, hi = att + 1.96 * se)

p <- ggplot(es_df, aes(event_time, att)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_vline(xintercept = 0, linetype = "dotted", color = "grey40") +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.2, fill = "steelblue") +
  geom_line(color = "steelblue", linewidth = 0.8) +
  geom_point(color = "steelblue") +
  labs(title = "CS Dynamic ATT: Cumulative Abnormal Return Around Breach Disclosure",
       subtitle = "Doubly-robust, breach-size weighted, clustered SEs (Event_ID)",
       x = "Event time (trading days, 0 = breach disclosure)",
       y = "Cumulative ATT (CAR)") +
  theme_minimal(base_size = 12)

ggsave("CS_event_study.png", p, width = 8, height = 5, dpi = 150)
print(p)

write_csv(es_df, "CS_event_study_estimates.csv")
saveRDS(att, "att_gt_object.rds")
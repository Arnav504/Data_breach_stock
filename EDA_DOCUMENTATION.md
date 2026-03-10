# Exploratory Data Analysis (EDA) Documentation  
## Data Breach Disclosures and Firm Financial Outcomes (Phase 2)

This document describes the exploratory data analysis performed on the breach disclosure and stock return data used to study how the market reacts to data breach announcements.

---

## 1. Objectives of the EDA

- **Describe the breach sample:** coverage, timing, breach types, and severity (records exposed).
- **Assess data quality:** missing values, confounded events, and stock data availability.
- **Summarize the market reaction:** distribution of cumulative abnormal returns (CAR) and how they vary by breach type and size.
- **Support empirical design:** inform event windows, controls, and heterogeneity analyses (e.g. log breach size, breach type dummies).
- **Check event-study assumptions:** pre-trends (no reaction before disclosure) and timing of the reaction.

---

## 2. Data Sources

| Source | Description | Use in analysis |
|--------|-------------|------------------|
| **Rosati & Lynn (2020)** | Data Breach Dataset, Mendeley Data (DOI: 10.17632/w33nhh3282.1). 506 breach events affecting NYSE/NASDAQ U.S. firms, April 2005–March 2015. Sourced from Privacy Rights Clearinghouse and enriched manually. | Primary breach-level data: event date, firm identifier (ticker), breach type, breach size, confound flag. |
| **Yahoo Finance (via tidyquant)** | Daily adjusted closing prices for each firm ticker and for the S&P 500 index (^GSPC). | Construction of daily log returns, market model (alpha, beta), and abnormal returns (AR) and cumulative abnormal returns (CAR). |

---

## 3. Data Structure and Variable Definitions

### 3.1 Raw breach dataset (after read-in)

The CSV contains one row per breach event. Key variables:

| Variable | Type | Description |
|----------|------|-------------|
| `Event_ID` | Numeric | Unique event identifier. |
| `ticker` | Character | Stock ticker symbol (e.g. BAC, JPM). Used to fetch stock prices. |
| `name` | Character | Firm name. |
| `event_date` | Date | Public disclosure date of the breach (day the market learns the news). |
| `event_year` | Numeric | Calendar year of disclosure. |
| `breach_type` | Character | Code: HACK, INSD, PORT, DISC, CARD, PHYS, STAT, UNKN (see labels below). |
| `breach_size` | Numeric | Number of records exposed (missing for some events). |
| `confound_dum` | Binary | 1 if a major concurrent announcement (e.g. earnings, merger) occurred within 10 days before disclosure; 0 otherwise. |
| `confound_type` | Character | Description of confound (e.g. "none"). |
| `event_state`, `hq_state` | Character | State where breach occurred / firm headquarters. |

**Breach type codes and labels:**

- **HACK** — Hacking / malware  
- **INSD** — Insider (employee or contractor)  
- **PORT** — Portable device (laptop, drive) lost or stolen  
- **DISC** — Unintended disclosure (e.g. misconfiguration, human error)  
- **CARD** — Card fraud  
- **PHYS** — Physical loss (paper, device)  
- **STAT** — Stationary device  
- **UNKN** — Unknown  

### 3.2 Cleaned breach dataset (`breaches`)

After cleaning and filtering:

- **Parsing:** `event_date` converted from character to Date (e.g. dd/mm/yyyy via `dmy()`).
- **Filtering:** Only breach types in the list above; rows with missing `ticker` or `event_date` dropped.
- **Derived:** `breach_type_label` = readable label for breach type; `breach_size` coerced to numeric (missing where not reported).
- **Variables retained:** Event_ID, ticker, name, event_date, event_year, breach_type, breach_type_label, breach_size, confound_dum, confound_type, hq_state.

### 3.3 Stock panel (`stock_panel`)

One row per **event–day** in the event window. Built after fetching prices and computing returns:

| Variable | Description |
|----------|-------------|
| `Event_ID`, `ticker`, `event_date` | Event and firm identifiers. |
| `date` | Calendar date of the observation. |
| `t` | Event time in trading days (0 = disclosure date; -5 to +10 in the main window). |
| `firm_ret` | Firm’s daily log return. |
| `mkt_ret` | S&P 500 daily log return. |
| `ar` | Abnormal return = firm_ret − expected return (from market model). |
| `car` | Cumulative abnormal return from start of window up to this day. |
| `car_0_10` | Cumulative abnormal return from t = 0 onward; at t = 10 equals CAR(0, +10). |
| `Post_it` | 1 if t ≥ 0, 0 otherwise (for TWFE-style specs). |
| `days_since_disclosure` | Same as t. |
| `breach_type`, `breach_type_label`, `breach_size`, `confound_dum`, `hq_state`, `event_year` | Merged from `breaches`. |

---

## 4. Data Cleaning and Filtering Steps

1. **Load raw CSV** — read "Data Breach Dataset.csv" (508 rows in raw file).
2. **Parse dates** — `event_date` with `dmy()`.
3. **Restrict breach types** — keep only HACK, INSD, PORT, DISC, CARD, PHYS, STAT, UNKN.
4. **Create breach_type_label** — map codes to readable names.
5. **Numeric breach_size** — `as.numeric(breach_size)`; missing where not reported.
6. **Drop incomplete rows** — remove rows with `NA` in `ticker` or `event_date`.
7. **Stock data:** For each event, fetch firm and S&P 500 prices; compute log returns; define event time `t`; use estimation window t ∈ [-200, -11] for market model; skip event if &lt; 60 trading days in estimation window or if price fetch fails (e.g. delisted ticker).
8. **Confounded events:** Kept in the dataset but excluded from main analysis and most figures (filter `confound_dum == 0` when reporting average CAR, regressions, and event-study plots).

---

## 5. Univariate Summary Statistics

### 5.1 Breach sample (cleaned `breaches`)

- **Number of events:** 506 (after filtering; raw has 508 rows, some may be dropped by filters).
- **Confounded events:** Share with `confound_dum == 1` (e.g. ~5–15%); reported in `breach_summary` table.
- **Breach size (records exposed):**
  - Many missing or zero; analysis uses `log(1 + breach_size)` or size bins.
  - When non-missing and positive: distribution is **highly right-skewed** (median much smaller than mean; long tail of very large breaches).
- **Temporal span:** event_year from 2005 to 2015.
- **Breach types:** PORT (portable device) and HACK/INSD/DISC are among the most frequent; distribution reported in `events_by_type` table.

### 5.2 Stock panel (event–day level)

- **Events with valid stock data:** Typically ~345 distinct Event_IDs (many tickers fail to load or have insufficient history — delisted, renamed, or data errors).
- **Skipped events:** Listed in `missing` (e.g. AMR, Kodak, ChoicePoint); documented as a limitation (delisted/renamed firms).
- **Event window:** Each event has up to 16 days in the panel (t = -5 to +10).

### 5.3 CAR(0, +10) (one row per event, non-confounded)

- **Summary stats:** n, mean, median, sd, min, max (in `car_summary` table).
- **Interpretation:** Negative mean/median indicates average stock underperformance in the 10 days after disclosure; dispersion (sd, min/max) shows substantial cross-sectional variation.

---

## 6. Temporal and Cross-Sectional EDA

### 6.1 Events by year

- **Plot:** Bar chart of number of disclosure events per calendar year (2005–2015).
- **Purpose:** Describe time coverage and trends (e.g. more disclosures in later years, possibly reflecting reporting or regulatory changes).
- **Typical pattern:** Counts often rise over the sample period, consistent with expanding state breach notification laws and greater awareness.

### 6.2 Events by breach type

- **Table:** Count of events in each `breach_type_label`.
- **Purpose:** Show which breach types dominate the sample (e.g. PORT, HACK, INSD, DISC).

### 6.3 Breach size distribution

- **Plot:** Histogram of breach size (in thousands of records), excluding missing and zero.
- **Finding:** Strong right skew; most events have relatively small reported sizes, with a long tail of very large breaches. Justifies use of log(1 + breach_size) and size bins in regressions and figures.

---

## 7. Event-Study and Outcome EDA

### 7.1 Average abnormal return by event day (mean AR by t)

- **Plot:** Bar chart of mean AR across non-confounded events for each t (about -5 to +10).
- **Purpose:** See **when** the market reacts. Bars near zero for t &lt; 0 support “no pre-trend”; negative bars at/after t = 0 indicate reaction at disclosure.
- **Interpretation:** Central to assessing event-study validity (parallel trends / no anticipation).

### 7.2 Average cumulative abnormal return by event day (mean CAR by t)

- **Plot:** Line (and points) of mean CAR over t.
- **Purpose:** Show how the **average cumulative penalty** builds over the event window.
- **Interpretation:** Flat near zero before t = 0; downward slope after t = 0 implies growing average loss post-disclosure.

### 7.3 CAR(0, +10) by breach type

- **Plot:** Horizontal bar chart of mean CAR(0, +10) for four types: Hacking, Insider, Portable Device, Unintended Disclosure (non-confounded).
- **Purpose:** Explore whether **breach type** is related to the size of the market penalty.
- **Interpretation:** More negative mean CAR for a type suggests a stronger average penalty for that type.

### 7.4 CAR(0, +10) by breach size bins

- **Plot:** Bar chart of mean CAR(0, +10) by size bin: Missing/0, &lt;1k, 1k–10k, 10k–100k, 100k+ records.
- **Purpose:** Explore **heterogeneity by severity** without imposing a linear log-size form.
- **Interpretation:** More negative means in larger bins support “larger breaches → larger penalty.”

### 7.5 Top 10 worst performers (Appendix Graph 1)

- **Plot:** Faceted line plot of CAR over t for the 10 events with the most negative CAR(0, +10) (non-confounded).
- **Purpose:** Illustrate **extreme negative reactions** and the time path of losses; highlights cross-sectional variation.

---

## 8. Visual EDA Summary

| Figure | Role in EDA | Main question |
|--------|-------------|----------------|
| Events by year | Describe sample | How does disclosure count vary over time? |
| Breach size histogram | Describe severity | How is breach size distributed? (right skew) |
| Mean AR by t | Event-study timing | When does the market react? (pre-trends, reaction at t=0) |
| Mean CAR by t | Event-study magnitude | How does average cumulative loss evolve? |
| CAR by breach type | Heterogeneity | Does penalty vary by type of breach? |
| CAR by size bin | Heterogeneity | Does penalty vary by breach size? |
| Top 10 worst | Extremes and paths | Who lost the most and how did CAR evolve? |

Detailed plot-by-plot explanations are in **PLOTS_EXPLANATION.md**.

---

## 9. Key EDA Findings (Summary)

- **Sample coverage:** 506 breach events (cleaned), 2005–2015; ~345 events with sufficient stock data for the event-study panel. Many missing/delisted tickers; skipped events documented.
- **Confounds:** A minority of events are confounded; main results and figures exclude them.
- **Breach size:** Highly right-skewed; many missing/zero; log and bin specifications used in analysis.
- **Temporal pattern:** Disclosure counts generally increase over the period; consistent with broader reporting and regulation.
- **Market reaction:** Mean CAR(0, +10) negative on average; substantial variation across events. Event-study plots used to check pre-trends and timing of reaction.
- **Heterogeneity:** Mean CAR varies by breach type and by size bin; supports inclusion of type and log(size) or size bins in regression models.

---

## 10. Limitations and Data Quality Notes

- **Selection:** Only firms with valid tickers and sufficient trading history enter the stock panel; delisted or renamed firms are excluded (e.g. AMR, Kodak).
- **Breach size:** Many missing or zero; results by size are conditional on non-missing size or on size bins that include “Missing/0.”
- **Confounds:** Events with concurrent major news are flagged and excluded from main analysis but remain in the dataset for robustness or alternative specs.
- **Event date:** We use **disclosure** date (when the market learns), not breach occurrence date.
- **Market model:** Single-factor (S&P 500) market model; estimation window t ∈ [-200, -11]; alternative windows (e.g. -1/+1, -3/+10) can be used for robustness.
- **Causality:** EDA is descriptive; selection into breach disclosure and into our sample may be non-random; main inference relies on event-study and regression design discussed in the Phase 2 document.

---

## 11. Code and Outputs

- **Scripts:** `Data_Breaches.R` (full analysis and comments); `Data_Breaches.Rmd` (knit-ready report).
- **Tables:** Breach summary, events by year, events by type, skipped events, CAR summary, regression output (see script/Rmd).
- **Figures:** All plots listed in Section 8 are produced by the script; explanations in **PLOTS_EXPLANATION.md**.

For exact numbers and updated summaries, run the R script or knit the Rmd and refer to the generated tables and figures.

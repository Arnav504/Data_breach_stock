# Callaway–Sant’Anna (CS) Estimator — Documentation

This document describes **`CS estimator.R`**: how the panel is built, how it maps into the **`did`** package (`att_gt`, `aggte`), and how to read outputs. It is meant to sit beside **`Data_Breaches.Rmd`**, which uses a **market-model event study**; the CS script uses a **different comparison group and outcome construction** (see [Comparison with the event-study script](#comparison-with-the-event-study-script)).

---

## 1. Purpose

**Research question (informal):** Around a **data breach disclosure**, how does the **cumulative stock return** of the affected firm evolve relative to a **benchmark** that tracks the **same calendar trading days**, holding the **market’s** path fixed in calendar time?

**Estimator:** [Callaway & Sant’Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001) group–time average treatment effects, implemented in R as **`did`** ([`bcallaway11/did`](https://github.com/bcallaway11/did)).

**Implementation file:** `CS estimator.R` (runs **two specifications** in one file; the second clears the workspace with `rm(list = ls())`).

---

## 2. Data inputs

| Input | Role |
|-------|------|
| `Data Breach Dataset.csv` | Breach-level rows: `Event_ID`, `ticker`, `event_date`, `breach_type`, `breach_size`, `confound_dum`, etc. |
| Yahoo Finance (via **`tidyquant`**) | Daily adjusted prices for **each firm ticker** and for **`^GSPC`** (S&P 500). |

**Cleaning (both blocks in `CS estimator.R`):**

- `event_date` parsed with **`lubridate::dmy()`**.
- **`breach_type`** restricted to: `INSD`, `PORT`, `DISC`, `CARD`, `STAT`, `UNKN` (note: **`HACK` and `PHYS` are excluded** here, unlike `Data_Breaches.Rmd`, which also keeps `HACK` and `PHYS`).
- **`confound_dum == 0`** only (no concurrent major confound in the source flag).
- Rows with missing **`ticker`** or **`event_date`** dropped.
- **`distinct(Event_ID, .keep_all = TRUE)`** keeps one row per event.

After cleaning, the script prints `nrow(breaches)` (count depends on the CSV and filters).

---

## 3. Economic design (intuition)

### 3.1 Treated vs control units

For **each breach event** the script creates **two synthetic “units”** that share the **same** event-time grid of **trading days**:

| Unit | `unit_id` | Role | Series |
|------|-----------|------|--------|
| **Treated** | `F_<Event_ID>` | Firm affected by the disclosure | Cumulative **firm** daily return from the start of the local window |
| **Control (“never treated”)** | `M_<Event_ID>` | **S&P 500** over the **identical** set of `trade_date`s aligned to that firm’s window | Cumulative **market** daily return from the same window start |

The S&P arm is labeled **never treated** in `att_gt` (`control_group = "nevertreated"`): it is a **cross-sectional control path** matched in **calendar time** to the firm’s window, not a separate firm.

### 3.2 Outcome `y`

**`y` = cumulative sum of daily simple returns** from the **first** trading day in the constructed window through each `event_time`.

- **Version 1:** returns from `tq_transmute` + `periodReturn` (default is **simple** returns unless `type` is set—here no `type = "log"`).
- **Version 2:** explicit **`ret = adjusted / lag(adjusted) - 1`**.

So `y` is a **level cumulative return** from the window origin, not the same object as the **log-return market-model CAR** in `Data_Breaches.Rmd`. It is still useful as a **cumulative performance gap** between firm and index **on the same dates**.

### 3.3 Event time

- **`event_time = 0`:** First **trading day on or after** `event_date` in the firm’s price series.
- Negative `event_time`: trading days **before** that anchor; positive: **after**.

---

## 4. Version 1 (lines ~1–163) — preliminary CS spec

### 4.1 Windows and filters

| Setting | Value |
|---------|--------|
| `window_pad` | 25 (calendar days used to **filter** `trade_date` around `event_date`; the usable grid is trading days inside that span) |
| `event_time` filter | **−15 to +15** trading days |
| Minimum rows | At least **25** trading days in the aligned window after filtering, else the event is dropped |

**Market data:** `tq_get("^GSPC", ...)` with `periodReturn` for `ret_mkt`. **Firm:** same for `ret_firm`.

### 4.2 Panel columns (Version 1)

| Column | Meaning |
|--------|---------|
| `Event_ID` | Breach id |
| `unit_id` | `F_*` (firm) or `M_*` (market) |
| `event_time` | Trading-day index, 0 = disclosure anchor |
| `y` | Cumulative return (firm or market) |
| `treat` | `1` = firm, `0` = market |
| `period` | `event_time + 15` (maps event time to **positive** integers for `did`) |
| `G` | **`0`** for market (never treated), **`15`** for firm (first treated period in this encoding) |
| `id_num` | Numeric id from `factor(paste(unit_id, Event_ID))` — unique per firm-event or market-event arm |
| `w` | Weights: **`log(breach_size + 1)`** for treated rows, **`1`** for control rows |

**Note:** Comments in the file mention `G = 16` in places; **Version 1 code sets `G = 15` for treated units**. The diagnostic `cat(..., sum(panel$G == 16), ...)` therefore does **not** count Version 1 treated rows correctly; use **`G == 15`** for treated in Version 1.

### 4.3 `att_gt` (Version 1)

```r
att_gt(
  yname = "y", tname = "period", idname = "id_num", gname = "G",
  weightsname = "w",
  data = panel,
  control_group = "nevertreated",
  panel = FALSE,
  bstrap = TRUE, cband = TRUE,
  est_method = "dr"
)
```

- **`panel = FALSE`:** Data are organized as **event × arm × time** stacked rows, not a classical long firm-year panel.
- **`est_method = "dr"`:** Doubly robust group–time ATT.
- **No `xformla`:** No additional covariates in the propensity / outcome models beyond what `did` uses by default for DR.

### 4.4 Aggregation and plot (Version 1)

```r
aggte(att, type = "dynamic", min_e = -15, max_e = 15, na.rm = TRUE)
```

- **`type = "dynamic"`:** Event-study style **relative** effects across `event_time` / equivalent.
- Plot uses **`ggplot2`** with **±1.96 × SE** ribbons (normal approximation). **Not saved to disk** in Version 1 (only `print(p)`).

---

## 5. Version 2 (lines ~165–367) — main documented spec

Version 2 **clears the environment** (`rm(list = ls())`), reloads libraries and data, and rebuilds a richer panel.

### 5.1 Data pull

| Setting | Value |
|---------|--------|
| `hist_pad` | **400** calendar days before the earliest breach (extra history for covariates) |
| `window_pad` | **25** calendar days around each event (same role as Version 1) |

Returns: **simple** returns from adjusted close for firm and S&P.

### 5.2 Event window and covariates

| Setting | Value |
|---------|--------|
| `event_time` | **−20 to +20** trading days (wider raw window than Version 1) |
| Minimum trading days | **25** in the aligned window (same idea as Version 1) |
| Covariates | Computed **per event** for **firm** and **market** arms separately |

**Covariate construction** (`compute_covars_firm` / `compute_covars_mkt`):

1. Take all trading days **strictly before** `event_date` for that ticker (firm) or for S&P (market).
2. Require at least **60** rows; else return `NA` and the whole event is dropped later.
3. **`est` window:** from the pre-event history, take **`slice_tail(n = 250)`** then **`slice_head(n = 220)`** — i.e. **220 trading days** drawn from the last **250** before the event (approximately trading days **−250 to −31** relative to the last pre-event day, not relative to disclosure; see code comments as “[-250, -30]” style pre-window).
4. **`pre_vol`:** `sd(est$ret)` (volatility of daily returns in that 220-day block).
5. **`pre_mom`:** `sum(est$ret)` (cumulative return / “momentum” over that block).
6. **`log_size`:** `log(last_row$adjusted)` where `last_row` is the **last available** pre-`event_date` **adjusted price** (level, not return).

If any covariate is `NA` for firm or market, **`build_event_window`** returns `NULL` for that event.

### 5.3 Panel columns (Version 2)

Same structure as Version 1, with these differences:

| Column | Version 2 |
|--------|-----------|
| `period` | `event_time + 16` |
| `G` | **`16`** for firm, **`0`** for market |
| `pre_vol`, `pre_mom`, `log_size` | Present on both arms (firm vs market pre-event stats) |
| `w_raw` | `log(pmax(breach_size, 1) + 1)` |
| `w` | `w_raw / mean(w_raw[treat == 1])` — **normalized** so the average treated weight is **1** |

**Filters before estimation:** finite `y`, `w`, valid `G` and `period`, and non-missing **`pre_mom`** and **`log_size`** (note: **`pre_vol` is not in this filter** despite being in the data).

### 5.4 `att_gt` (Version 2)

```r
att_gt(
  yname = "y", tname = "period", idname = "id_num", gname = "G",
  xformla = ~ pre_mom + log_size,
  data = panel,
  control_group = "nevertreated",
  weightsname = "w",
  panel = FALSE,
  bstrap = TRUE, biters = 1000, cband = TRUE,
  est_method = "dr"
)
```

- **`pre_vol` is omitted** from `xformla` even though it is computed (reserved for extensions or diagnostics).
- **`biters = 1000`:** Number of bootstrap draws for inference.

### 5.5 Aggregation (Version 2)

```r
aggte(att, type = "dynamic", min_e = -15, max_e = 18, na.rm = TRUE)
```

Dynamic effects from **15** periods before to **18** after the reference normalization used by `aggte` (aligned with the wider **−20…+20** window where supported by the fit).

### 5.6 Outputs written to disk (Version 2 only)

| File | Contents |
|------|----------|
| `CS_event_study.png` | Dynamic ATT plot (8×5 in, 150 dpi) |
| `CS_event_study_estimates.csv` | Columns: `event_time`, `att`, `se`, `lo`, `hi` (95% normal bands: `att ± 1.96*se`) |
| `att_gt_object.rds` | Full **`att_gt`** object (`readRDS` for `summary()`, plotting, or alternate `aggte` calls) |

---

## 6. How to run

1. Set the R **working directory** to the project folder (where `Data Breach Dataset.csv` lives).
2. Ensure packages: **`tidyverse`**, **`tidyquant`**, **`lubridate`**, **`did`**.
3. Run:

```r
source("CS estimator.R")
```

**Runtime:** Depends on Yahoo throttling and the number of tickers; Version 2 pulls a **longer** price history (`hist_pad = 400`) than Version 1.

**Reproducibility:** `set.seed(42)` is set before estimation; bootstrap still involves randomness unless `did` fixes the stream internally for all steps.

---

## 7. Reading the dynamic ATT plot

- **Horizontal axis:** Event time in **trading days** (0 = first trading day on/after disclosure in the firm series).
- **Vertical axis:** Aggregated **group–time ATT** from `aggte`, expressed in the same units as contrasts in **`y`** (cumulative simple returns over the window from the window start).
- **Zero line:** Reference for “no differential cumulative effect” relative to the estimand defined by `did` and your `G` / `period` coding.
- **Ribbon:** Approximate **95%** interval using **1.96 × standard error** from the dynamic aggregation output.

Exact definitions of each `egt` (event time relative to treatment) follow **`did`** documentation for `aggte(..., type = "dynamic")` given your `G` and calendar indexing.

---

## 8. Comparison with the event-study script

| Aspect | `Data_Breaches.Rmd` / `Data_Breaches.R` | `CS estimator.R` |
|--------|----------------------------------------|------------------|
| **Expected return** | OLS market model on **t ∈ [−200, −11]** | No alpha/beta; comparison is **cumulative firm vs cumulative S&P** on same dates |
| **Returns** | **Log** daily returns (`periodReturn`, `type = "log"`) | **Simple** daily returns (V2 explicit; V1 via `periodReturn`) |
| **CAR** | AR relative to fitted model; **`car_0_10`** from **t ≥ 0** | **`y`** = cumsum from **window start** (includes pre-disclosure portion of the window) |
| **Inference** | Mostly descriptive + `lm` on CAR(0,+10) | **`did`**: DR `att_gt`, bootstrap, `aggte` dynamic |
| **Sample filters** | Includes **`HACK`**, **`PHYS`**; confounds often excluded in tables/plots | **Stricter breach types**; **`confound_dum == 0` in the breach table** |

Do **not** expect point estimates to match across the two pipelines; they answer **related** but **not identical** questions.

---

## 9. Limitations and caveats

1. **Synthetic control interpretation:** The S&P path is not a formal **Synthetic Control Method** unit; it is a **benchmark arm** entered as “never treated” in **`did`** for each stacked pseudo-panel.
2. **Causal language:** Results are only as credible as the **identifying assumptions** for stacking, timing, and the DR model; **parallel trends** should be argued in calendar/event time, not assumed by the code.
3. **Ticker / data loss:** Events are dropped when prices are missing, windows are short, or covariates are `NA`.
4. **Weights:** Treated observations are upweighted by breach size (log); controls get weight 1 (V1) or normalized weights (V2). Interpretation is **WATT**-style (weighted ATT), not necessarily equal-weight across firms.
5. **Comment vs code:** Version 1 **`G`** value and sanity-check printout may disagree; rely on the **`ifelse(treat == 1L, 15, 0)`** line for Version 1 behavior.
6. **Subtitle in ggplot (Version 2):** Mentions clustering by `Event_ID`; verify in **`did`** output and `?att_gt` whether clustering matches your intended correlation structure for stacked firm/market pairs.

---

## 10. References

- Callaway, B., & Sant’Anna, P. H. C. (2021). Difference-in-differences with multiple time periods. *Journal of Econometrics*.
- **`did` R package:** [https://bcallaway11.github.io/did/](https://bcallaway11.github.io/did/)
- Breach data citation: Rosati & Lynn (2020), Mendeley Data, DOI **10.17632/w33nhh3282.1** (see **`README.md`**).

---

## 11. File maintenance

If you rename **`CS estimator.R`** or split Version 1 and Version 2 into separate scripts, update this document and **`README.md`** so paths and “what runs by default” stay accurate.

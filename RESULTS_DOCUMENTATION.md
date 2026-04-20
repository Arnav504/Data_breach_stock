# Project Results Documentation

This document reports the **quantified results** for the project and explains what they mean.

Run date used for values below: **2026-04-20**.

---

## 1. Research question

How do stock prices react when a firm publicly discloses a data breach?

Two analysis branches are used:

1. **Classic event study** (`Data_Breaches.R` / `Data_Breaches.Rmd`)
2. **Callaway-Sant'Anna / DID branch** (`CS estimator.R`)

---

## 2. Data and sample counts (exact)

### 2.1 Event-study branch sample

| Metric | Value |
|---|---:|
| Raw breach rows (`Data Breach Dataset.csv`) | 508 |
| Cleaned breach events used in event-study code | 506 |
| Confounded events (`confound_dum == 1`) | 185 |
| Confounded share | 36.56% |
| Distinct events in stock panel (after price/history filters) | 343 |
| Event-day rows in stock panel | 5,488 |
| Non-confounded events used for CAR(0,+10) cross-section (`t == 10`) | 224 |

### 2.2 CS branch sample (`CS estimator.R`)

| Metric | Value |
|---|---:|
| Clean breach events after CS filters | 223 |
| Distinct tickers pulled (Version 2 printout) | 133 |
| Never-treated rows in final panel (Version 2) | 2,624 |
| Treated rows in final panel (Version 2) | 2,624 |
| Unique `id_num` units (Version 2) | 150 |

---

## 3. Event-study quantified results

### 3.1 Core CAR(0,+10) outcome (non-confounded events)

| Statistic | Value |
|---|---:|
| Mean CAR(0,+10) | -0.001218 |
| Median CAR(0,+10) | 0.000748 |
| Standard deviation | 0.065066 |

Interpretation:

- The **mean** is slightly negative (about -0.12% in return units).
- The **median** is slightly positive, which indicates a skewed distribution with downside tail events.

### 3.2 Event-time AR/CAR summary

| Metric | Value |
|---|---:|
| Mean AR for pre-disclosure days (`t < 0`) | 0.000772 |
| Mean AR for post-disclosure days (`t >= 0`) | -0.000111 |
| Mean CAR at `t = 10` (from CAR path that starts at `t = -5`) | 0.002644 |

Important note:

- `mean_CAR_t10` is based on `car` that accumulates from `t = -5`.
- `mean_car_0_10` is post-only accumulation and is the better summary of post-disclosure impact; this is the negative value shown above.

### 3.3 Cross-sectional OLS results

Model 1: `car_0_10 ~ log_breach_size + factor(breach_type)`

| Statistic | Value |
|---|---:|
| Coefficient on `log_breach_size` | -0.002325 |
| p-value on `log_breach_size` | 0.232181 |
| R-squared | 0.027345 |

Model 2: `car_0_10 ~ factor(breach_type)`

| Statistic | Value |
|---|---:|
| R-squared | 0.109129 |

Interpretation:

- The sign on breach size is negative, but **not statistically strong** in this specification.
- Breach-type-only model explains more variation than size-plus-type in this run (R2 comparison), though both remain low/modest.

### 3.4 Heterogeneity by breach type (mean CAR(0,+10), non-confounded)

| Breach type | N | Mean CAR(0,+10) |
|---|---:|---:|
| Stationary Device | 3 | -0.178000 |
| Unknown | 6 | -0.007430 |
| Physical Loss | 9 | -0.005620 |
| Insider | 43 | -0.002960 |
| Hacking | 56 | -0.002370 |
| Portable Device | 53 | 0.002520 |
| Unintended Disclosure | 40 | 0.005230 |
| Card Fraud | 14 | 0.019500 |

Interpretation:

- Estimates vary widely by type, but small cells (for example `n = 3`) are unstable and should be interpreted carefully.

### 3.5 Heterogeneity by breach size bins (mean CAR(0,+10), non-confounded)

| Size bin | N | Mean CAR(0,+10) |
|---|---:|---:|
| Missing/0 | 124 | -0.002190 |
| <1k | 32 | 0.001190 |
| 1k-10k | 25 | 0.009920 |
| 10k-100k | 17 | -0.005160 |
| 100k+ | 26 | -0.007680 |

Interpretation:

- Larger bins (`10k-100k`, `100k+`) are more negative than smaller bins in this run.
- The relationship is not perfectly monotone because of sample composition and small bin counts.

---

## 4. CS estimator quantified results

### 4.1 Version 2 overall dynamic ATT summary (`aggte`)

From the `CS estimator.R` run:

| Metric | Value |
|---|---:|
| Overall ATT (dynamic aggregation) | -0.2237 |
| Standard error | 0.1023 |
| 95% CI | [-0.4241, -0.0233] |
| Pre-trend test p-value (`att_gt`) | 0.91266 |

Interpretation:

- Overall dynamic ATT is negative and the reported 95% interval excludes zero.
- Pre-trend test does not reject parallel trends in this run (high p-value).

### 4.2 Dynamic effects (`CS_event_study_estimates.csv`)

Selected event times:

| Event time | ATT | SE | 95% CI (`lo`, `hi`) |
|---:|---:|---:|---:|
| -15 | 0.033791 | 0.072768 | [-0.108834, 0.176416] |
| -1 | 0.030341 | 0.145010 | [-0.253879, 0.314560] |
| 0 | -0.055552 | 0.156608 | [-0.362504, 0.251401] |
| 5 | -0.221903 | 0.159902 | [-0.535311, 0.091505] |
| 10 | -0.206048 | 0.175236 | [-0.549510, 0.137414] |
| 15 | -0.298136 | 0.180753 | [-0.652412, 0.056139] |
| 18 | -0.509203 | 0.256267 | [-1.011486, -0.006920] |

Interpretation:

- Post-disclosure effects trend more negative at later event times in this run.
- Most individual event-time intervals include zero; the strongest negative tail is at event time `18`.

---

## 5. Bottom-line results statement

Using the event-study branch, the **post-only average CAR(0,+10)** is slightly negative (`-0.001218`) with substantial dispersion (`sd = 0.065066`) across events. Cross-sectional patterns suggest heterogeneity by breach type and size bins, but coefficient-level evidence on log breach size is weak in the baseline OLS (`p = 0.232181`).

Using the CS branch, the **overall dynamic ATT** is negative (`-0.2237`, 95% CI `[-0.4241, -0.0233]`) with no strong pre-trend rejection (`p = 0.91266`), and dynamic point estimates become more negative at later post-event horizons.

---

## 6. Reproducibility and files

To regenerate the numbers in this document:

1. Run the event-study pipeline (`Data_Breaches.R` or `Data_Breaches.Rmd`) and compute summary metrics from the resulting `stock_panel`.
2. Run `CS estimator.R` to regenerate:
   - `CS_event_study.png`
   - `CS_event_study_estimates.csv`
   - `att_gt_object.rds`
3. Record run date and package versions when preparing final submission tables.


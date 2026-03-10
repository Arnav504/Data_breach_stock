# Explanation of the Plots

This document explains each figure produced by the Data Breach Disclosures analysis (Phase 2).

---

## 1. Top 10 Worst Stock Performers After Data Breach Disclosure (Appendix Graph 1)

**What it is:** A faceted line plot: 10 panels, one per breach event.

**What it shows:**
- **X-axis:** Event time `t` in trading days relative to the disclosure date (t = 0 is the day the breach is made public; range about -5 to +10).
- **Y-axis:** **Cumulative abnormal return (CAR)** for that event — the sum of daily abnormal returns from the start of the window up to each day.
- **Each panel:** One firm’s CAR path (ticker and event month in the strip). Events are the 10 with the **most negative** CAR(0, +10) (i.e. biggest 10-day loss after disclosure), excluding confounded events.

**How to read it:**
- The **vertical dashed line** at t = 0 marks the disclosure date.
- A line **dropping** after t = 0 means the stock underperformed the market in the days following the breach news.
- The **red shaded area** below zero highlights the cumulative loss. Steeper drops and deeper shading mean a stronger negative market reaction.

**Purpose:** Shows that some firms experience large, persistent negative returns after a breach is disclosed; useful for the “worst cases” discussion and for illustrating cross-sectional variation.

---

## 2. Average 10-Day Cumulative Abnormal Return by Breach Type (Appendix Graph 2)

**What it is:** A horizontal bar chart.

**What it shows:**
- **Y-axis:** Four breach types — Hacking, Insider, Portable Device, Unintended Disclosure.
- **X-axis:** **Mean CAR(0, +10)** — average 10-day cumulative abnormal return across all non-confounded events in that type.
- **Bar color:** Red for negative mean CAR, teal for positive.

**How to read it:**
- Bars to the **left of zero** (negative) = on average, that breach type is associated with a stock decline in the 10 days after disclosure.
- Longer bars = larger average loss (or gain). Comparing lengths across types shows which breach types the market “punishes” more.

**Purpose:** Tests whether the **type** of breach (how it happened) is related to the size of the market penalty. Complements the regression of CAR on breach type.

---

## 3. Average Abnormal Return by Event Day

**What it is:** A bar chart of **mean abnormal return (AR)** by event day.

**What it shows:**
- **X-axis:** Event day `t` (about -5 to +10).
- **Y-axis:** **Mean AR** across all non-confounded events on that day — i.e. the average “surprise” return (actual return minus expected from the market model).
- **Vertical dashed line** at t = 0 = disclosure date.

**How to read it:**
- **Bars near zero** before t = 0 support “no pre-trend” (market wasn’t reacting before the news).
- **Negative bars** around t = 0 or right after = on average the market reacts negatively on and immediately after the disclosure.
- **Bar height** = magnitude of the average daily reaction on that day.

**Purpose:** Standard event-study plot for **when** the market reacts. Shows whether the effect is concentrated at disclosure (t = 0) or spread over several days.

---

## 4. Average Cumulative Abnormal Return by Event Day

**What it is:** A line (and points) plot of **mean CAR** over event time.

**What it shows:**
- **X-axis:** Event day `t` (same as above).
- **Y-axis:** **Mean CAR** — at each day t, the average across events of the cumulative abnormal return from the start of the window up to t.
- **Vertical dashed line** at t = 0 = disclosure.

**How to read it:**
- **Flat near zero** before t = 0 again suggests no pre-disclosure reaction.
- **Downward slope** after t = 0 = average cumulative loss grows in the days after disclosure.
- **Level at t = 10** is the average CAR(0, +10) in the sample.

**Purpose:** Shows the **build-up** of the average penalty over the event window. Complements the daily AR plot by focusing on cumulative effect.

---

## 5. Average CAR(0,+10) by Breach Size (records exposed)

**What it is:** A bar chart of mean CAR(0, +10) by **breach size bin**.

**What it shows:**
- **X-axis:** Size bins — Missing/0, &lt;1k, 1k–10k, 10k–100k, 100k+ (number of records exposed).
- **Y-axis:** **Mean CAR(0, +10)** within each bin (non-confounded events only).
- **Bar color:** Red = negative mean CAR, teal = positive.

**How to read it:**
- More **negative** bars for **larger** size bins suggest the market penalizes bigger breaches more.
- If smaller bins are near zero or positive and larger bins are negative, that supports “larger breaches → larger penalty.”

**Purpose:** Heterogeneity by **severity** (size). Does not assume a linear effect; lets the data show whether the relationship is monotone or concentrated in certain size ranges.

---

## 6. Data Breach Disclosures by Year

**What it is:** A simple bar chart of **count of events per year**.

**What it shows:**
- **X-axis:** Calendar year (2005–2015 in the sample).
- **Y-axis:** Number of breach disclosure events in that year.

**How to read it:**
- **Rising** bars over time can reflect more disclosures (e.g. more breaches, better reporting, or stricter notification laws).
- **Peaks** in certain years can motivate discussion of policy or data availability.

**Purpose:** Describes the **time coverage** of the sample and supports any narrative about trends in breach disclosure.

---

## 7. Distribution of Breach Size (records exposed)

**What it is:** A **histogram** of breach size.

**What it shows:**
- **X-axis:** Breach size in **thousands of records** (only events with non-missing, positive size).
- **Y-axis:** Count of events in each bin.

**How to read it:**
- **Right-skewed** shape = most breaches are small (few records), with a long tail of very large breaches (e.g. millions of records).
- This skew is why the analysis uses **log(1 + breach_size)** in regressions and size bins in the bar chart.

**Purpose:** EDA to describe **severity** and justify log/binned specifications. Matches the “highly right-skewed” description in the Phase 2 document.

---

## Summary Table

| Plot | Main question | Key takeaway |
|------|----------------|--------------|
| Top 10 worst | Who lost the most? | Illustrates extreme negative reactions and paths over time. |
| CAR by breach type | Does penalty depend on type? | Compare mean CAR across Hacking, Insider, Portable Device, Unintended Disclosure. |
| Mean AR by t | When does the market react? | Look for negative bars at/after t = 0. |
| Mean CAR by t | How does cumulative loss evolve? | Downward slope after t = 0 = growing average penalty. |
| CAR by size bin | Does penalty depend on severity? | Compare mean CAR across size bins. |
| Events by year | How does sample vary over time? | Describes temporal coverage and trends. |
| Breach size histogram | How is severity distributed? | Right-skew; motivates log/bins in analysis. |

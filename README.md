# Smart Meter Insights & Tariff Optimisation

**Portfolio project:** Python, Pandas, psycopg, PostgreSQL, pytest, Power BI-ready CSVs. No frontend.

## Source and grain

The ESB Networks **Non-personal DUoS Group Averaged 30-minute Interval Meter Data** reports present aggregated average import/export **power in kW**. The observed August 2026 subset provided for inspection contains **144 rows: 48 half-hour slots for each of DG1, DG2, DG5**. It describes **one typical day per group for the month**, not daily individual observations or national grid demand. The reporting month is represented as the first day of its month *solely as a database identifier*.

Official source: https://www.esbnetworks.ie/about-us/company/data-and-digital/non-personal-smart-meter-data

The source states the data is DST-based but does not establish in the verified FAQ whether its time labels refer to starts or ends. The provided CSV begins 00:30 and ends 00:00 for DG1, suggesting (but not proving) interval-end labels. **`mapping.json` defaults to `slot_label: end` as a documented analytical assumption.** If the supplier documentation confirms a different convention, set it to `start`, reload in a new database or remove affected imports, and rerun queries. The analytical SQL converts a labelled 00:00 end to 23:30 start by subtracting 30 minutes. August avoids DST clock-change ambiguity.

Power to energy: **average interval kW × 0.5 hours = average interval kWh**. These kWh are *representative average-meter* interval values. Summing 48 intervals gives a **typical-day energy estimate**, not measured monthly customer consumption or a verified bill. No weekday/weekend inference is possible.



## Local setup

1. Create venv: `python -m venv .venv` and activate (`.venv\Scripts\Activate.ps1` in Windows PowerShell).
2. `python -m pip install -r requirements.txt`
3. Create PostgreSQL database `smart_meter_insights` in pgAdmin and open its Query Tool.
4. Execute `sql/01_schema.sql`, then `sql/02_analytics.sql` **on a fresh database**. This v2 schema replaces the old `fact_half_hour` model; old analytical views may need to be dropped if you already created them.
5. Copy `.env.example` to `.env`, configure `DATABASE_URL` (do **not** commit `.env`).
6. Put your legally downloaded ESB CSV at `data/august2026.csv` (not committed). Run `python -m src.pipeline inspect data/august2026.csv`.
7. Copy `mapping.example.json` to `mapping.json`; review `slot_label` assumption.
8. `python -m src.pipeline load data/august2026.csv --mapping mapping.json`
9. In pgAdmin: `SELECT duos_group, reporting_month, count(*) FROM meter.fact_monthly_profile GROUP BY 1,2;` Expect DG1/DG2/DG5 with 48 slots each for the observed 144-row file.
10. `python -m pytest -q`; `python -m src.export`.
11. In Power BI import CSVs from `outputs/` to visualise typical hourly profile, peak share, and hypothetical scenario costs.

If the actual CSV contains many more groups, months, or another record grain, re-inspect and adapt before importing. No real ESB CSV is included with this repo.

## Analytical outputs

- `v_hourly`: typical hourly import/export kWh by group and month.
- `v_daily_profile`: summed 48-slot **typical day**, not observations for a calendar date.
- `v_peak_exposure`: typical peak interval share, with 17:00–19:00 defined on inferred interval start.
- `v_tariff_comparison`: illustrative **energy-only** daily charge under deliberately hypothetical rates, excludes taxes, standing charges and export credits.
- `v_shift_sensitivity`: hypothetical effect of moving 5%, 10%, 15% of peak kWh to off-peak while preserving kWh.

## Product analytics framing

**Potential product:** personalised peak-hour usage advisory. **Hypothesis:** relevant alerts may increase voluntary shifting of flexible demand. **Outcome metric:** measured percentage of eligible peak kWh shifted in a future consent-based controlled trial. **Guardrails:** total daily kWh, customer opt-out, cost. The published averaged data **cannot measure product adoption, retention, individual tariff fit, causal impact, or A/B test uplift**. This project makes analytical recommendations, not claims about a running product experiment.

## Data dictionary

| Field | Meaning |
|---|---|
| `duos_group` | ESB published DUoS group identifier |
| `reporting_month` | Normalised first-of-month reporting label; **not an observed day** |
| `interval_time` | Local time label from source |
| `slot_label` | Explicit assumption: `start` or `end` of interval |
| `interval_start_time` | Derived local interval start used for tariff windows |
| `import_kw`, `export_kw` | Aggregated average meter power over 30 minutes, kW |
| `import_kwh`, `export_kwh` | Representative interval energy, kW × 0.5 h |
| `shift_share` | Hypothetical fraction of peak energy moved |
| `hypothetical_daily_saving_eur` | Modelled energy-only saving per representative day |



# Data visualisations


<img width="422" height="415" alt="image" src="https://github.com/user-attachments/assets/8de7f2b3-56ff-430e-a91b-237b86a7380c" />

## Executive Dashboard

### Project Highlights

- Analysed 144 aggregated smart-meter profile records
  across three DUoS groups.
- Developed a Python ETL pipeline with PostgreSQL
  storage and automated data validation.
- Created analytical SQL views for electricity usage,
  hypothetical tariffs and load-shifting scenarios.
- Built a Power BI dashboard communicating consumption
  trends, modelled costs and potential savings.

### Technologies
Python | Pandas | PostgreSQL | SQL | psycopg |
pytest | Power BI


## Known limitations and validation

Python unit tests exercise parsing and units, but **live PostgreSQL integration, actual dataset import, and real-world findings remain unverified until executed locally**. The source file format was checked using user-provided inspection outputs; never claim a successful live ingestion without confirming database row counts. The project uses no invented individual customer records, no artificially dated daily readings, and no estimated experiment results.

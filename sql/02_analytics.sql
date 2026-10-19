-- REQUIRES 01_schema.sql. No actual daily or weekday-level data is present.
-- Assumption: tariff is applied to the interval START time.
-- For source labels indicating END times, subtract 30 minutes (00:00 maps to 23:30).
CREATE OR REPLACE VIEW meter.v_profile AS
SELECT f.*, (f.interval_time - CASE WHEN f.slot_label='end' THEN INTERVAL '30 minutes' ELSE INTERVAL '0 minutes' END)::time AS interval_start_time
FROM meter.fact_monthly_profile f;

CREATE OR REPLACE VIEW meter.v_hourly AS
SELECT reporting_month,duos_group,EXTRACT(HOUR FROM interval_start_time)::int AS hour_local,
 SUM(import_kwh) AS typical_hour_import_kwh,SUM(export_kwh) AS typical_hour_export_kwh,
 COUNT(*) AS interval_count
FROM meter.v_profile GROUP BY 1,2,3;

CREATE OR REPLACE VIEW meter.v_daily_profile AS
SELECT reporting_month,duos_group,
 SUM(import_kwh) AS typical_day_import_kwh,SUM(export_kwh) AS typical_day_export_kwh,
 COUNT(*) AS interval_count
FROM meter.v_profile GROUP BY 1,2;

CREATE OR REPLACE VIEW meter.v_peak_exposure AS
SELECT reporting_month,duos_group,
 SUM(import_kwh) FILTER (WHERE interval_start_time >= TIME '17:00' AND interval_start_time < TIME '19:00') AS typical_peak_import_kwh,
 SUM(import_kwh) AS typical_day_import_kwh,
 ROUND(100 * SUM(import_kwh) FILTER (WHERE interval_start_time >= TIME '17:00' AND interval_start_time < TIME '19:00') / NULLIF(SUM(import_kwh),0),2) AS peak_share_pct
FROM meter.v_profile GROUP BY 1,2;

CREATE OR REPLACE VIEW meter.v_tariff_comparison AS
SELECT p.reporting_month,p.duos_group,t.name AS scenario,
 SUM(p.import_kwh) AS typical_day_import_kwh,
 SUM(p.import_kwh * CASE WHEN EXTRACT(HOUR FROM p.interval_start_time)>=t.peak_start_hour
 AND EXTRACT(HOUR FROM p.interval_start_time)<t.peak_end_hour
 THEN t.peak_eur_kwh ELSE t.offpeak_eur_kwh END) AS hypothetical_daily_energy_cost_eur
FROM meter.v_profile p CROSS JOIN meter.tariff_scenario t GROUP BY 1,2,3;

CREATE OR REPLACE VIEW meter.v_shift_sensitivity AS
WITH peak AS (
 SELECT p.reporting_month,p.duos_group,t.name AS scenario,t.peak_eur_kwh,t.offpeak_eur_kwh,
 COALESCE(SUM(p.import_kwh) FILTER (WHERE EXTRACT(HOUR FROM p.interval_start_time)>=t.peak_start_hour
 AND EXTRACT(HOUR FROM p.interval_start_time)<t.peak_end_hour),0) AS peak_kwh
 FROM meter.v_profile p CROSS JOIN meter.tariff_scenario t GROUP BY 1,2,3,4,5
)
SELECT p.reporting_month,p.duos_group,p.scenario,s.shift_share,p.peak_kwh,
 p.peak_kwh*s.shift_share*(p.peak_eur_kwh-p.offpeak_eur_kwh) AS hypothetical_daily_saving_eur
FROM peak p CROSS JOIN (VALUES (0.05::numeric),(0.10::numeric),(0.15::numeric)) s(shift_share);

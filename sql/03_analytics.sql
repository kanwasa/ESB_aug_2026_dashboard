SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'meter'
  AND table_name = 'fact_monthly_profile'
ORDER BY ordinal_position;

SELECT
    duos_group,
    COUNT(*) AS total_intervals
FROM meter.fact_monthly_profile
GROUP BY duos_group
ORDER BY duos_group;

SELECT
    duos_group,
    reporting_month,
    COUNT(*) AS interval_count,
    ROUND(SUM(import_kwh), 4) AS profile_daily_import_kwh,
    ROUND(SUM(export_kwh), 4) AS profile_daily_export_kwh
FROM meter.fact_monthly_profile
GROUP BY duos_group, reporting_month
ORDER BY duos_group;


SELECT * FROM meter.v_hourly LIMIT 10;

SELECT * FROM meter.v_tariff_comparison LIMIT 10;

SELECT * FROM meter.v_shift_sensitivity LIMIT 10;



WITH hourly_usage AS (
    SELECT
        duos_group,
        reporting_month,
        EXTRACT(HOUR FROM interval_time)::int AS hour_of_day,
        SUM(import_kwh) AS hourly_import_kwh
    FROM meter.fact_monthly_profile
    GROUP BY
        duos_group,
        reporting_month,
        EXTRACT(HOUR FROM interval_time)
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY duos_group, reporting_month
            ORDER BY hourly_import_kwh DESC
        ) AS peak_rank
    FROM hourly_usage
)
SELECT
    duos_group,
    reporting_month,
    hour_of_day,
    ROUND(hourly_import_kwh, 4) AS hourly_import_kwh
FROM ranked
WHERE peak_rank <= 3
ORDER BY duos_group, peak_rank;
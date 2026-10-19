CREATE SCHEMA IF NOT EXISTS meter;
CREATE TABLE IF NOT EXISTS meter.ingestion_file (
 file_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 filename TEXT NOT NULL, sha256 TEXT NOT NULL UNIQUE,
 loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(), row_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS meter.staging_raw (
 file_id BIGINT NOT NULL REFERENCES meter.ingestion_file(file_id),
 source_row_number INT NOT NULL, source_record JSONB NOT NULL,
 PRIMARY KEY(file_id, source_row_number)
);
CREATE TABLE IF NOT EXISTS meter.dim_duos_group (duos_group TEXT PRIMARY KEY);
-- Reporting month is a label only, never a claim that a reading was made on day 1.
CREATE TABLE IF NOT EXISTS meter.fact_monthly_profile (
 file_id BIGINT NOT NULL REFERENCES meter.ingestion_file(file_id),
 source_row_number INT NOT NULL,
 duos_group TEXT NOT NULL REFERENCES meter.dim_duos_group(duos_group),
 reporting_month DATE NOT NULL,
 interval_time TIME NOT NULL,
 slot_label TEXT NOT NULL CHECK (slot_label IN ('start','end')),
 import_kw NUMERIC(16,6) NOT NULL CHECK(import_kw >= 0),
 export_kw NUMERIC(16,6) CHECK(export_kw >= 0),
 import_kwh NUMERIC(16,6) GENERATED ALWAYS AS (import_kw * 0.5) STORED,
 export_kwh NUMERIC(16,6) GENERATED ALWAYS AS (export_kw * 0.5) STORED,
 PRIMARY KEY (file_id,source_row_number),
 UNIQUE (file_id,duos_group,reporting_month,interval_time),
 CHECK (EXTRACT(MINUTE FROM interval_time) IN (0,30) AND EXTRACT(SECOND FROM interval_time)=0)
);
CREATE INDEX IF NOT EXISTS ix_profile_group_month ON meter.fact_monthly_profile(duos_group,reporting_month);
-- Prices are deliberately hypothetical, EUR/kWh; energy-only, no taxes or fixed costs.
CREATE TABLE IF NOT EXISTS meter.tariff_scenario (
 scenario_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name TEXT NOT NULL UNIQUE,
 offpeak_eur_kwh NUMERIC(10,5) NOT NULL CHECK(offpeak_eur_kwh>=0),
 peak_eur_kwh NUMERIC(10,5) NOT NULL CHECK(peak_eur_kwh>=0),
 peak_start_hour INTEGER NOT NULL CHECK(peak_start_hour BETWEEN 0 AND 23),
 peak_end_hour INTEGER NOT NULL CHECK(peak_end_hour BETWEEN 1 AND 24),
 CHECK(peak_start_hour < peak_end_hour)
);
INSERT INTO meter.tariff_scenario(name,offpeak_eur_kwh,peak_eur_kwh,peak_start_hour,peak_end_hour)
VALUES ('HYPOTHETICAL_PEAK_17_19',0.20,0.40,17,19)
ON CONFLICT (name) DO NOTHING;

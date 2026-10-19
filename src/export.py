"""Power BI CSV exports from PostgreSQL analytical views."""
import os
from pathlib import Path
import pandas as pd
import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / '.env')
OUTPUT = ROOT / 'outputs'
VIEWS = ['v_hourly', 'v_daily_profile', 'v_peak_exposure', 'v_tariff_comparison', 'v_shift_sensitivity']


def main():
    OUTPUT.mkdir(exist_ok=True)
    with psycopg.connect(os.environ['DATABASE_URL']) as conn:
        for view in VIEWS:
            with conn.cursor() as cur:
                cur.execute(f'SELECT * FROM meter.{view}')  # fixed, trusted allowlist
                rows = cur.fetchall()
                columns = [c.name for c in cur.description]
            pd.DataFrame(rows, columns=columns).to_csv(OUTPUT / f'{view}.csv', index=False, encoding='utf-8-sig')
            print(f'{view}: {len(rows)} rows')


if __name__ == '__main__':
    main()

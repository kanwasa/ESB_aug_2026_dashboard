"""Ingest ESB monthly DUoS group-average 48-slot profiles (not daily observations)."""
import argparse
import csv
import hashlib
import json
import logging
import os
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv

LOG = logging.getLogger('meter')
HEADERS = {'group': 'DUoS Group', 'month': 'MONTH', 'time': 'Interval timestamp',
           'import_kw': 'Avg Active Import interval data',
           'export_kw': 'Avg Active Export interval data'}


def inspect_csv(path):
    with open(path, newline='', encoding='utf-8-sig') as f:
        for i, row in enumerate(csv.reader(f)):
            print(f'LINE {i+1}: {row[:15]}')
            if i >= 5:
                break
    print('Expected grain: reporting month + DUoS group + 30-minute time-of-day slot.')


def normalise_number(value):
    if value is None or pd.isna(value) or str(value).strip() == '':
        return None
    try:
        number = Decimal(str(value).strip().replace(',', ''))
    except InvalidOperation as exc:
        raise ValueError(f'Invalid number: {value!r}') from exc
    if not number.is_finite() or number < 0:
        raise ValueError(f'Negative or non-finite power: {value!r}')
    return number


def normalise_chunk(chunk, mapping, header_row=1):
    fields = [mapping[k] for k in ('group', 'month', 'time', 'import_kw', 'export_kw')]
    missing = set(fields) - set(chunk.columns)
    if missing:
        raise ValueError(f'Missing columns: {sorted(missing)}; found {list(chunk.columns)}')
    good, bad = [], []
    for index, row in chunk.iterrows():
        source_row = int(index) + header_row + 1
        try:
            group = str(row[mapping['group']]).strip()
            if not group:
                raise ValueError('Missing group')
            month = datetime.strptime(str(row[mapping['month']]).strip(), '%b-%y').date().replace(day=1)
            slot = datetime.strptime(str(row[mapping['time']]).strip(), '%H:%M:%S').time()
            if slot.minute not in (0, 30) or slot.second != 0:
                raise ValueError('Slot is not on 30-minute boundary')
            imp = normalise_number(row[mapping['import_kw']])
            exp = normalise_number(row[mapping['export_kw']])
            if imp is None:
                raise ValueError('Missing import kW')
            good.append((source_row, group, month, slot, imp, exp))
        except (ValueError, TypeError) as exc:
            bad.append((source_row, str(exc)))
    return good, bad


def load_file(csv_path, mapping_path, dsn, chunksize=10000):
    import psycopg
    path = Path(csv_path)
    mapping = json.loads(Path(mapping_path).read_text(encoding='utf-8'))
    if mapping.get('record_layout') != 'monthly_profile' or mapping.get('unit') != 'kW':
        raise ValueError('Expected monthly_profile records with power unit kW')
    if mapping.get('slot_label') not in ('start', 'end'):
        raise ValueError('Explicit slot_label start/end is required for tariff scenarios')
    header_row = int(mapping.get('header_row', 1))
    if header_row < 1:
        raise ValueError('header_row must be >= 1')
    file_hash = hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
    total = 0
    keys = set()
    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute('SELECT 1 FROM meter.ingestion_file WHERE sha256=%s', (file_hash,))
            if cur.fetchone():
                raise ValueError('File already imported')
            cur.execute('INSERT INTO meter.ingestion_file(filename, sha256) VALUES (%s, %s) RETURNING file_id',
                        (path.name, file_hash))
            file_id = cur.fetchone()[0]
            for chunk in pd.read_csv(path, header=header_row-1, chunksize=chunksize,
                                     dtype=str, keep_default_na=False, encoding='utf-8-sig'):
                chunk.index = range(total, total + len(chunk))
                good, bad = normalise_chunk(chunk, mapping, header_row)
                if bad:
                    raise ValueError(f'Invalid rows (first 10): {bad[:10]}')
                for _, group, month, slot, _, _ in good:
                    key = (group, month, slot)
                    if key in keys:
                        raise ValueError(f'Duplicate month/group/slot: {key}')
                    keys.add(key)
                with cur.copy('COPY meter.staging_raw(file_id, source_row_number, source_record) FROM STDIN') as cp:
                    for index, record in chunk.iterrows():
                        cp.write_row((file_id, int(index) + header_row + 1,
                                      json.dumps(record.to_dict(), ensure_ascii=False)))
                for group in sorted({g[1] for g in good}):
                    cur.execute('INSERT INTO meter.dim_duos_group(duos_group) VALUES(%s) ON CONFLICT DO NOTHING', (group,))
                with cur.copy('COPY meter.fact_monthly_profile(file_id, source_row_number, duos_group, reporting_month, interval_time, import_kw, export_kw, slot_label) FROM STDIN') as cp:
                    for row, group, month, slot, imp, exp in good:
                        cp.write_row((file_id, row, group, month, slot, imp, exp, mapping['slot_label']))
                total += len(chunk)
                LOG.info('Staged and validated %d rows', total)
            cur.execute('UPDATE meter.ingestion_file SET row_count=%s WHERE file_id=%s', (total, file_id))
    print(f'Loaded {total} monthly-profile records as file_id={file_id}')


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('inspect').add_argument('file')
    load = commands.add_parser('load')
    load.add_argument('file')
    load.add_argument('--mapping', default='mapping.json')
    load.add_argument('--chunksize', type=int, default=10000)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format='%(levelname)s %(message)s')
    if args.command == 'inspect':
        inspect_csv(args.file)
    else:
        load_dotenv(Path(__file__).resolve().parent.parent / '.env')
        dsn = os.getenv('DATABASE_URL')
        if not dsn:
            raise SystemExit('DATABASE_URL missing in .env')
        load_file(args.file, args.mapping, dsn, args.chunksize)


if __name__ == '__main__':
    main()

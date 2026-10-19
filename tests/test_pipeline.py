from decimal import Decimal
import pandas as pd
import pytest
from src.pipeline import normalise_chunk, normalise_number

M = {'group': 'DUoS Group', 'month': 'MONTH', 'time': 'Interval timestamp',
     'import_kw': 'Avg Active Import interval data', 'export_kw': 'Avg Active Export interval data'}


def test_power_to_energy():
    assert normalise_number('0.2602') * Decimal('0.5') == Decimal('0.13010')
    with pytest.raises(ValueError):
        normalise_number('-2')


def test_valid_monthly_profile():
    data = pd.DataFrame([{'DUoS Group': 'DG1', 'MONTH': 'Aug-26',
                          'Interval timestamp': '00:30:00',
                          'Avg Active Import interval data': '0.2602',
                          'Avg Active Export interval data': '0.0292'}])
    good, bad = normalise_chunk(data, M)
    assert not bad
    assert good[0][1] == 'DG1'
    assert good[0][2].isoformat() == '2026-08-01'
    assert good[0][4] == Decimal('0.2602')


def test_invalid_slot():
    data = pd.DataFrame([{'DUoS Group': 'DG1', 'MONTH': 'Aug-26',
                          'Interval timestamp': '17:15:00',
                          'Avg Active Import interval data': '2',
                          'Avg Active Export interval data': '0'}])
    assert normalise_chunk(data, M)[1]

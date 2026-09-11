from datetime import date, datetime, timezone

import logging

import pytest

import app.scheduler as scheduler
from app.scheduler import run_iteration, should_run


def test_scheduler_selects_tomorrow_run_once_after_07_bangkok():
    now = datetime(2026, 1, 2, 0, 1, tzinfo=timezone.utc)  # 07:01 Asia/Bangkok
    assert should_run(now, date(2026, 1, 1)) is True
    assert should_run(now, date(2026, 1, 2)) is False


def test_scheduler_does_not_run_before_07_bangkok():
    now = datetime(2026, 1, 1, 23, 59, tzinfo=timezone.utc)  # 06:59 Asia/Bangkok
    assert should_run(now, date(2025, 12, 31)) is False


def test_daily_iteration_does_not_advance_date_when_processing_fails(monkeypatch):
    now = datetime(2026, 1, 2, 0, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(scheduler, 'run_daily_once', lambda db, today: (_ for _ in ()).throw(RuntimeError('db down')))

    with pytest.raises(RuntimeError, match='db down'):
        run_iteration(object(), date(2026, 1, 1), now=now)


def test_scheduler_iteration_returns_new_date_only_after_success(monkeypatch):
    now = datetime(2026, 1, 2, 0, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(scheduler, 'run_daily_once', lambda db, today: 3)

    last_run, sent, failed, daily = run_iteration(object(), date(2026, 1, 1), now=now)

    assert (last_run, sent, failed, daily) == (date(2026, 1, 2), 3, 0, True)


def test_scheduler_iteration_rolls_back_and_continues_after_error(monkeypatch, caplog):
    class BrokenSession:
        def rollback(self):
            self.rolled_back = True

    session = BrokenSession()
    monkeypatch.setattr(scheduler, 'run_delivery_once', lambda db: (_ for _ in ()).throw(ConnectionError('temporary')))

    with caplog.at_level(logging.ERROR):
        result = scheduler.try_iteration(session, date(2026, 1, 1), now=datetime(2026, 1, 1, tzinfo=timezone.utc))

    assert result == (date(2026, 1, 1), False)
    assert session.rolled_back is True
    assert 'ConnectionError' in caplog.text

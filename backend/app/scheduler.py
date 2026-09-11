"""Daily notification and push outbox worker."""
from __future__ import annotations

import logging
import time
from datetime import datetime
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.push import claim_push_outbox, deliver_claimed, enqueue_push_outbox

LOGGER = logging.getLogger(__name__)
BANGKOK = ZoneInfo("Asia/Bangkok")
RUN_HOUR = 7
POLL_SECONDS = 30


def run_daily_once(db: Session, today=None) -> int:
    """Generate reminders and enqueue idempotent per-subscription deliveries."""
    from app.notifications import generate_daily_reminders
    generate_daily_reminders(db, today=today)
    enqueue_push_outbox(db)
    sent, _failed = deliver_claimed(db, claim_push_outbox(db))
    return sent


def run_delivery_once(db: Session, limit: int = 100) -> tuple[int, int]:
    """Claim and deliver durable work; safe to call after a worker restart."""
    return deliver_claimed(db, claim_push_outbox(db, limit=limit))


def should_run(now: datetime, last_run_date) -> bool:
    local_now = now.astimezone(BANGKOK)
    return local_now.hour >= RUN_HOUR and last_run_date != local_now.date()


def run_iteration(db: Session, last_run_date, now: datetime | None = None):
    """Run one scheduler iteration; return the date only after daily work succeeds."""
    now = now or datetime.now(BANGKOK)
    if should_run(now, last_run_date):
        sent = run_daily_once(db, today=now.date())
        return now.date(), sent, 0, True
    sent, failed = run_delivery_once(db)
    return last_run_date, sent, failed, False


def try_iteration(db: Session, last_run_date, now: datetime | None = None):
    """Keep transient iteration failures from terminating the worker."""
    try:
        new_date, sent, failed, daily = run_iteration(db, last_run_date, now=now)
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        LOGGER.exception("scheduler iteration failed type=%s", type(exc).__name__)
        return last_run_date, False
    if daily:
        LOGGER.info("daily reminders completed date=%s push_deliveries=%d", new_date, sent)
    elif sent or failed:
        LOGGER.info("push outbox processed sent=%d failed=%d", sent, failed)
    return new_date, True


def main() -> None:
    import app.main  # noqa: F401
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    last_run_date = None
    backoff = 1
    while True:
        now = datetime.now(BANGKOK)
        db = None
        try:
            db = SessionLocal()
            last_run_date, succeeded = try_iteration(db, last_run_date, now=now)
            backoff = 1 if succeeded else min(POLL_SECONDS, backoff * 2)
        except Exception as exc:  # noqa: BLE001
            if db is not None:
                db.rollback()
            LOGGER.exception("scheduler loop failed type=%s", type(exc).__name__)
            backoff = min(POLL_SECONDS, backoff * 2)
        finally:
            if db is not None:
                db.close()
        time.sleep(backoff if backoff > 1 else POLL_SECONDS)


if __name__ == "__main__":
    main()

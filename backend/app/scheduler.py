"""Daily notification worker for the production scheduler container."""
from __future__ import annotations

import logging
import time
from collections import defaultdict
from datetime import datetime
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import Notification
from app.push import send_to_owner

LOGGER = logging.getLogger(__name__)
BANGKOK = ZoneInfo("Asia/Bangkok")
RUN_HOUR = 7
POLL_SECONDS = 30


def run_daily_once(db: Session, today=None) -> int:
    """Create reminders and send only reminders inserted by this run."""
    from app.notifications import generate_daily_reminders

    before = set(db.scalars(select(Notification.id)).all())
    reminders = generate_daily_reminders(db, today=today)
    fresh = [item for item in reminders if item.id not in before]
    by_owner = defaultdict(list)
    for item in fresh:
        by_owner[item.owner_id].append(item)

    sent = 0
    for owner_id, items in by_owner.items():
        for item in items:
            payload = {
                "notificationId": str(item.id),
                "title": item.title,
                "body": item.body,
                "url": "/#/notifications",
            }
            sent += send_to_owner(db, owner_id, payload)
    return sent


def should_run(now: datetime, last_run_date) -> bool:
    local_now = now.astimezone(BANGKOK)
    return local_now.hour >= RUN_HOUR and last_run_date != local_now.date()


def main() -> None:
    # Load the FastAPI module first; notifications.py imports its auth dependency.
    import app.main  # noqa: F401

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    last_run_date = None
    while True:
        now = datetime.now(BANGKOK)
        if should_run(now, last_run_date):
            with SessionLocal() as db:
                sent = run_daily_once(db, today=now.date())
            last_run_date = now.date()
            LOGGER.info("daily reminders completed date=%s push_deliveries=%d", last_run_date, sent)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()

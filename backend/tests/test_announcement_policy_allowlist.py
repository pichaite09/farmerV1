"""Evaluate the actual SQL eligibility expression on synthetic in-memory rows."""
from sqlalchemy import create_engine, select, text
from app.announcement_policy import eligible_notification_clause
from app.models import Notification


def test_unknown_kind_cannot_bypass_announcement_boundary():
    database = create_engine('sqlite://')
    with database.begin() as connection:
        connection.execute(text('CREATE TABLE notifications (id TEXT, kind TEXT, announcement_id TEXT, created_at TEXT)'))
        connection.execute(text('CREATE TABLE announcements (id TEXT, created_at TEXT)'))
        connection.execute(text('CREATE TABLE announcement_delivery_policy (singleton BOOLEAN, activated_at TEXT)'))
        connection.execute(text("INSERT INTO announcement_delivery_policy VALUES (1, '2026-01-01')"))
        connection.execute(text("INSERT INTO announcements VALUES ('new-campaign', '2026-02-01')"))
        connection.execute(text("INSERT INTO notifications VALUES ('legacy', 'legacy_announcement', NULL, '2000-01-01'), ('task', 'task_due_tomorrow', NULL, '2000-01-01'), ('unknown-linked', 'legacy_announcement', 'new-campaign', '2026-02-01')"))
        # Select only raw string IDs, avoiding the ORM UUID result processor.
        query = select(Notification.id).where(eligible_notification_clause())
        raw = str(query.compile(database, compile_kwargs={'literal_binds': True}))
        assert connection.exec_driver_sql(raw).scalars().all() == ['task']
    database.dispose()

"""Database-persisted, fail-closed announcement activation boundary.

Applies only to announcement push and sending old drafts, never inbox reads or
legitimate task reminders. No process-local time/env default can reopen history.
"""
from sqlalchemy import Boolean, DateTime, column, select, table

policy = table('announcement_delivery_policy', column('singleton', Boolean),
               column('activated_at', DateTime(timezone=True)))


def announcement_delivery_cutoff(db):
    return db.scalar(select(policy.c.activated_at).where(policy.c.singleton.is_(True)))


def announcement_allowed(db, announcement):
    cutoff = announcement_delivery_cutoff(db)
    return (cutoff is not None and announcement is not None
            and announcement.created_at is not None and announcement.created_at >= cutoff)


def eligible_notification_clause():
    """SQL predicate shared by enqueue, stale lease recovery and claim selection."""
    from sqlalchemy import and_, or_
    from app.models import Announcement, Notification
    cutoff = select(policy.c.activated_at).where(policy.c.singleton.is_(True)).scalar_subquery()
    return or_(
        and_(Notification.kind == 'task_due_tomorrow', Notification.announcement_id.is_(None)),
        and_(Notification.kind == 'admin_announcement', Notification.created_at >= cutoff, select(Announcement.id).where(
            Announcement.id == Notification.announcement_id,
            Announcement.created_at >= cutoff,
        ).exists()),
    )


def notification_allowed(db, notification_id):
    from app.models import Notification
    return db.scalar(select(Notification.id).where(
        Notification.id == notification_id, eligible_notification_clause(),
    )) is not None

"""Owner-scoped Web Push subscriptions and durable delivery."""
import json
import logging
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import func, or_, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db, settings
from app.models import Notification, PushOutbox, PushSubscription, FcmDeviceToken, Task, User, Announcement, AnnouncementRecipient
from app.schemas import PushSubscriptionCreate, PushSubscriptionOut, PushSubscriptionPatch

try:
    from pywebpush import webpush as pywebpush
except ImportError:  # pragma: no cover
    pywebpush = None

router = APIRouter(prefix='/api/v1/push')
_bearer = HTTPBearer(auto_error=False)
_logger = logging.getLogger(__name__)
LEASE_SECONDS = 300
MAX_ATTEMPTS = 5


def current_push_session(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer), db: Session = Depends(get_db)):
    from app.main import farmer_session
    return farmer_session(credentials, db)


def _out(subscription: PushSubscription) -> PushSubscriptionOut:
    return PushSubscriptionOut.model_validate({'id': subscription.id, 'endpoint': subscription.endpoint,
        'keys': {'p256dh': subscription.p256dh, 'auth': subscription.auth},
        'created_at': subscription.created_at, 'updated_at': subscription.updated_at})


def send_web_push(subscription: dict, payload: dict) -> bool:
    """Validate the endpoint before invoking the provider, then send one push."""
    try:
        validated = PushSubscriptionCreate.model_validate(subscription)
    except ValueError:
        return False
    if not settings.vapid_private_key or not settings.vapid_subject or pywebpush is None:
        return False
    pywebpush(subscription_info=validated.model_dump(by_alias=False), data=json.dumps(payload),
              vapid_private_key=settings.vapid_private_key, vapid_claims={'sub': settings.vapid_subject}, timeout=10)
    return True


def send_to_owner(db: Session, owner_id: uuid.UUID, payload: dict) -> int:
    """Compatibility helper for callers that need immediate fan-out."""
    sent = 0
    owner = db.scalar(select(User).where(User.id == owner_id))
    if owner is None or owner.status != 'active':
        return 0
    subscriptions = db.scalars(select(PushSubscription).where(PushSubscription.owner_id == owner_id)).all()
    for subscription in subscriptions:
        try:
            if send_web_push({'endpoint': subscription.endpoint, 'keys': {'p256dh': subscription.p256dh, 'auth': subscription.auth}}, payload):
                sent += 1
        except Exception as exc:  # noqa: BLE001
            status_code = getattr(getattr(exc, 'response', None), 'status_code', None)
            if status_code in {404, 410}:
                db.delete(subscription)
            _logger.warning('web push delivery failed for subscription %s: %s', subscription.id, type(exc).__name__)
    db.commit()
    return sent


def enqueue_push_outbox(db: Session, notifications: list[Notification] | None = None, owner_id: uuid.UUID | None = None, commit: bool = True) -> int:
    """Enqueue one idempotent delivery per notification and current subscription."""
    query = select(Notification).where(Notification.kind.in_(['task_due_tomorrow', 'admin_announcement']))
    if notifications is not None:
        ids = [n.id for n in notifications]
        if not ids:
            return 0
        query = query.where(Notification.id.in_(ids))
    if owner_id is not None:
        query = query.where(Notification.owner_id == owner_id)
    rows = db.scalars(query).all()
    added = 0
    announcement_ids = set()
    for notification in rows:
        task = db.get(Task, notification.task_id) if notification.task_id else None
        announcement = db.get(Announcement, notification.announcement_id) if notification.announcement_id else None
        if notification.announcement_id:
            announcement_ids.add(notification.announcement_id)
        if (notification.kind == 'task_due_tomorrow' and (task is None or task.status in {'completed', 'cancelled'})) or (notification.kind == 'admin_announcement' and (announcement is None or announcement.status == 'cancelled')) or notification.dismissed_at is not None:
            continue
        payload = {'notificationId': str(notification.id), 'title': notification.title,
                   'body': notification.body, 'url': '/#/notifications'}
        if announcement is not None and announcement.image_attachment_id:
            payload['announcementImageId'] = str(announcement.image_attachment_id)
            payload['announcementType'] = announcement.announcement_type
        subscriptions = db.scalars(select(PushSubscription).join(User, User.id == PushSubscription.owner_id).where(
            PushSubscription.owner_id == notification.owner_id, User.status == 'active',
        )).all()
        devices = db.scalars(select(FcmDeviceToken).where(
            FcmDeviceToken.owner_id == notification.owner_id, FcmDeviceToken.active.is_(True),
        )).all()
        if notification.announcement_id and not subscriptions and not devices:
            db.execute(update(AnnouncementRecipient).where(
                AnnouncementRecipient.announcement_id == notification.announcement_id,
                AnnouncementRecipient.user_id == notification.owner_id,
                AnnouncementRecipient.status == 'pending',
            ).values(status='suppressed'))
        for subscription in subscriptions:
            result = db.execute(insert(PushOutbox).values(
                owner_id=notification.owner_id, notification_id=notification.id,
                subscription_id=subscription.id, payload=payload,
            ).on_conflict_do_nothing(index_elements=['notification_id', 'subscription_id'])
             .returning(PushOutbox.id))
            # PostgreSQL reports -1 for rowcount when RETURNING is used.
            added += len(result.scalars().all())
        for device in devices:
            result = db.execute(insert(PushOutbox).values(
                owner_id=notification.owner_id, notification_id=notification.id,
                fcm_device_id=device.id, subscription_id=None, payload=payload,
            ).on_conflict_do_nothing(index_elements=['notification_id', 'fcm_device_id'])
             .returning(PushOutbox.id))
            added += len(result.scalars().all())
    now = datetime.now(timezone.utc)
    for announcement_id in announcement_ids:
        pending = db.scalar(select(func.count()).select_from(AnnouncementRecipient).where(
            AnnouncementRecipient.announcement_id == announcement_id,
            AnnouncementRecipient.status == 'pending',
        ))
        if not pending:
            _update_announcement_lifecycle(db, announcement_id, now)
    if commit:
        db.commit()
    return added


def claim_push_outbox(db: Session, limit: int = 100, now: datetime | None = None) -> list[PushOutbox]:
    """Atomically claim available work; stale claims are safely recoverable."""
    now = now or datetime.now(timezone.utc)
    stale = now - timedelta(seconds=LEASE_SECONDS)
    db.execute(update(PushOutbox).where(PushOutbox.status == 'claimed', PushOutbox.claimed_at < stale)
               .values(status='pending', claimed_at=None))
    rows = db.scalars(select(PushOutbox).where(
        or_(PushOutbox.status == 'pending',
            (PushOutbox.status == 'claimed') & (PushOutbox.claimed_at < stale)),
        PushOutbox.next_attempt_at <= now,
    ).order_by(PushOutbox.created_at, PushOutbox.id).limit(limit).with_for_update(skip_locked=True)).all()
    for row in rows:
        row.status = 'claimed'
        row.claimed_at = now
        row.attempts += 1
        notification = db.get(Notification, row.notification_id)
        if notification is not None and notification.announcement_id:
            _update_announcement_lifecycle(db, notification.announcement_id, now)
    db.commit()
    return rows


def _retry_delay(attempts: int) -> int:
    return min(3600, 60 * (2 ** max(0, attempts - 1)))


def deliver_claimed(db: Session, rows: list[PushOutbox], now: datetime | None = None) -> tuple[int, int]:
    """Deliver claims independently so one bad subscription cannot block others."""
    now = now or datetime.now(timezone.utc)
    sent = failed = 0
    for row in rows:
        subscription = db.get(PushSubscription, row.subscription_id) if row.subscription_id else None
        device = db.get(FcmDeviceToken, row.fcm_device_id) if row.fcm_device_id else None
        notification = db.get(Notification, row.notification_id)
        owner = db.scalar(select(User).where(User.id == row.owner_id).with_for_update())
        if owner is None or owner.status != 'active':
            if notification is not None and notification.announcement_id:
                db.execute(update(AnnouncementRecipient).where(
                    AnnouncementRecipient.announcement_id == notification.announcement_id,
                    AnnouncementRecipient.user_id == row.owner_id,
                    AnnouncementRecipient.status == 'pending',
                ).values(status='suppressed'))
            row.status, row.claimed_at, row.last_error = 'failed', None, 'suppressed'
            if notification is not None and notification.announcement_id:
                _update_announcement_lifecycle(db, notification.announcement_id, now)
            db.commit()
            failed += 1
            continue
        task = db.get(Task, notification.task_id) if notification is not None and notification.task_id else None
        announcement = db.get(Announcement, notification.announcement_id) if notification is not None and notification.announcement_id else None
        if announcement is not None:
            announcement = db.scalar(select(Announcement).where(Announcement.id == announcement.id).with_for_update())
        if notification is None or (notification.kind == 'task_due_tomorrow' and (task is None or task.status in {'completed', 'cancelled'})) or (notification.kind == 'admin_announcement' and (announcement is None or announcement.status == 'cancelled')) or notification.dismissed_at is not None:
            if notification is not None and notification.announcement_id:
                db.execute(update(AnnouncementRecipient).where(AnnouncementRecipient.announcement_id == notification.announcement_id, AnnouncementRecipient.user_id == notification.owner_id).values(status='suppressed'))
            row.status, row.claimed_at, row.last_error = 'failed', None, 'suppressed'
            if notification is not None and notification.announcement_id:
                _update_announcement_lifecycle(db, notification.announcement_id, now)
            db.commit()
            failed += 1
            continue
        try:
            if row.fcm_device_id:
                from app.fcm import send_fcm
                if device is None or not device.active:
                    raise ValueError('device token no longer active')
                send_fcm(device.token, row.payload)
            else:
                if subscription is None:
                    raise ValueError('subscription no longer exists')
                ok = send_web_push({'endpoint': subscription.endpoint,
                    'keys': {'p256dh': subscription.p256dh, 'auth': subscription.auth}}, row.payload)
                if not ok:
                    raise RuntimeError('web push is not configured')
        except Exception as exc:  # noqa: BLE001
            status_code = getattr(getattr(exc, 'response', None), 'status_code', None)
            if status_code in {404, 410} and subscription is not None:
                db.delete(subscription)
            row.last_error = type(exc).__name__
            row.claimed_at = None
            if row.attempts >= MAX_ATTEMPTS:
                row.status = 'failed'
                failed += 1
            else:
                row.status = 'pending'
                row.next_attempt_at = now + timedelta(seconds=_retry_delay(row.attempts))
            _logger.warning('web push delivery failed for outbox %s: %s', row.id, type(exc).__name__)
        else:
            row.status, row.sent_at, row.claimed_at = 'sent', now, None
            sent += 1
        _update_announcement_lifecycle(db, notification.announcement_id, now) if notification is not None and notification.announcement_id else None
        db.commit()
    return sent, failed


def _update_announcement_lifecycle(db: Session, announcement_id: uuid.UUID, now: datetime) -> None:
    """Set sending/sent/completed from terminal states without reviving cancel."""
    announcement = db.get(Announcement, announcement_id)
    if announcement is None or announcement.status == 'cancelled':
        return
    recipients = db.scalars(select(AnnouncementRecipient).where(
        AnnouncementRecipient.announcement_id == announcement_id,
    )).all()
    for recipient in recipients:
        _update_announcement_recipient(db, recipient)
    statuses = [recipient.status for recipient in recipients]
    outbox_statuses = db.scalars(select(PushOutbox.status).join(
        Notification, Notification.id == PushOutbox.notification_id,
    ).where(Notification.announcement_id == announcement_id)).all()
    if announcement.status in {'sent', 'completed'}:
        return
    if any(status in {'pending', 'claimed'} for status in outbox_statuses):
        announcement.status = 'sending'
    elif statuses and all(status in {'sent', 'failed', 'suppressed'} for status in statuses):
        # ``sent`` means at least one provider delivery succeeded. A campaign
        # whose recipients all lacked subscriptions or permanently failed has
        # completed, but was not sent.
        if 'sent' in statuses:
            announcement.status, announcement.sent_at = 'sent', announcement.sent_at or now
        else:
            announcement.status = 'completed'


def _update_announcement_recipient(db: Session, recipient: AnnouncementRecipient) -> None:
    """Recompute one recipient from every subscription delivery for its user."""
    outboxes = db.scalars(select(PushOutbox).join(
        Notification, Notification.id == PushOutbox.notification_id,
    ).where(
        Notification.announcement_id == recipient.announcement_id,
        PushOutbox.owner_id == recipient.user_id,
    )).all()
    if not outboxes:
        return
    statuses = {outbox.status for outbox in outboxes}
    if statuses & {'pending', 'claimed'}:
        recipient.status = 'pending'
    elif 'sent' in statuses:
        recipient.status = 'sent'
    elif recipient.status != 'suppressed':
        recipient.status = 'failed'


def _owned(db: Session, owner_id: uuid.UUID, subscription_id: uuid.UUID):
    subscription = db.scalar(select(PushSubscription).where(PushSubscription.id == subscription_id, PushSubscription.owner_id == owner_id))
    if subscription is None:
        raise HTTPException(404, 'Subscription not found')
    return subscription

@router.get('/vapid-public-key')
def vapid_public_key(identity=Depends(current_push_session)):
    if not settings.vapid_public_key:
        raise HTTPException(503, 'Web Push is not configured')
    return {'publicKey': settings.vapid_public_key}

@router.post('/subscriptions', status_code=201, response_model=PushSubscriptionOut)
def register_subscription(body: PushSubscriptionCreate, identity=Depends(current_push_session), db: Session = Depends(get_db)):
    owner_id = identity[1].id
    existing = db.scalar(select(PushSubscription).where(PushSubscription.endpoint == body.endpoint))
    if existing is not None:
        if existing.owner_id != owner_id: raise HTTPException(409, 'Subscription endpoint already registered')
        existing.p256dh, existing.auth = body.keys.p256dh, body.keys.auth
        db.commit(); db.refresh(existing); return _out(existing)
    subscription = PushSubscription(owner_id=owner_id, endpoint=body.endpoint, p256dh=body.keys.p256dh, auth=body.keys.auth)
    db.add(subscription)
    try: db.commit()
    except IntegrityError:
        db.rollback(); raise HTTPException(409, 'Subscription endpoint already registered')
    db.refresh(subscription); return _out(subscription)

@router.get('/subscriptions/{subscription_id}', response_model=PushSubscriptionOut)
def get_subscription(subscription_id: uuid.UUID, identity=Depends(current_push_session), db: Session = Depends(get_db)): return _out(_owned(db, identity[1].id, subscription_id))

@router.patch('/subscriptions/{subscription_id}', response_model=PushSubscriptionOut)
def update_subscription(subscription_id: uuid.UUID, body: PushSubscriptionPatch, identity=Depends(current_push_session), db: Session = Depends(get_db)):
    subscription = _owned(db, identity[1].id, subscription_id); changes = body.model_dump(exclude_unset=True)
    if 'endpoint' in changes:
        conflict = db.scalar(select(PushSubscription).where(PushSubscription.endpoint == changes['endpoint'], PushSubscription.id != subscription.id))
        if conflict is not None: raise HTTPException(409, 'Subscription endpoint already registered')
        subscription.endpoint = changes['endpoint']
    if body.keys is not None: subscription.p256dh, subscription.auth = body.keys.p256dh, body.keys.auth
    db.commit(); db.refresh(subscription); return _out(subscription)

@router.delete('/subscriptions/{subscription_id}', status_code=204)
def delete_subscription(subscription_id: uuid.UUID, identity=Depends(current_push_session), db: Session = Depends(get_db)):
    db.delete(_owned(db, identity[1].id, subscription_id)); db.commit(); return Response(status_code=204)

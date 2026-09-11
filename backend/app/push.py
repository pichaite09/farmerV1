"""Owner-scoped Web Push subscriptions and durable delivery."""
import json
import logging
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import or_, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db, settings
from app.models import Notification, PushOutbox, PushSubscription, Task
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
    from app.main import current_session
    return current_session(credentials, db)


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


def enqueue_push_outbox(db: Session, notifications: list[Notification] | None = None, owner_id: uuid.UUID | None = None) -> int:
    """Enqueue one idempotent delivery per notification and current subscription."""
    query = select(Notification).where(Notification.kind == 'task_due_tomorrow')
    if notifications is not None:
        ids = [n.id for n in notifications]
        if not ids:
            return 0
        query = query.where(Notification.id.in_(ids))
    if owner_id is not None:
        query = query.where(Notification.owner_id == owner_id)
    rows = db.scalars(query).all()
    added = 0
    for notification in rows:
        task = db.get(Task, notification.task_id)
        if task is None or task.status in {'completed', 'cancelled'} or notification.dismissed_at is not None:
            continue
        payload = {'notificationId': str(notification.id), 'title': notification.title,
                   'body': notification.body, 'url': '/#/notifications'}
        subscriptions = db.scalars(select(PushSubscription).where(PushSubscription.owner_id == notification.owner_id)).all()
        for subscription in subscriptions:
            result = db.execute(insert(PushOutbox).values(
                owner_id=notification.owner_id, notification_id=notification.id,
                subscription_id=subscription.id, payload=payload,
            ).on_conflict_do_nothing(index_elements=['notification_id', 'subscription_id'])
             .returning(PushOutbox.id))
            # PostgreSQL reports -1 for rowcount when RETURNING is used.
            added += len(result.scalars().all())
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
    db.commit()
    return rows


def _retry_delay(attempts: int) -> int:
    return min(3600, 60 * (2 ** max(0, attempts - 1)))


def deliver_claimed(db: Session, rows: list[PushOutbox], now: datetime | None = None) -> tuple[int, int]:
    """Deliver claims independently so one bad subscription cannot block others."""
    now = now or datetime.now(timezone.utc)
    sent = failed = 0
    for row in rows:
        subscription = db.get(PushSubscription, row.subscription_id)
        notification = db.get(Notification, row.notification_id)
        task = db.get(Task, notification.task_id) if notification is not None else None
        if notification is None or task is None or task.status in {'completed', 'cancelled'} or notification.dismissed_at is not None:
            row.status, row.claimed_at, row.last_error = 'failed', None, 'suppressed'
            db.commit()
            failed += 1
            continue
        try:
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
        db.commit()
    return sent, failed


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

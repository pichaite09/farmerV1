"""Owner-scoped Web Push subscriptions and delivery."""
import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db, settings
from app.models import PushSubscription
from app.schemas import PushSubscriptionCreate, PushSubscriptionOut, PushSubscriptionPatch

try:
    from pywebpush import webpush as pywebpush
except ImportError:  # pragma: no cover - dependency is installed in deployment
    pywebpush = None

router = APIRouter(prefix='/api/v1/push')
_bearer = HTTPBearer(auto_error=False)


def current_push_session(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
):
    from app.main import current_session
    return current_session(credentials, db)


def _out(subscription: PushSubscription) -> PushSubscriptionOut:
    return PushSubscriptionOut.model_validate({
        'id': subscription.id,
        'endpoint': subscription.endpoint,
        'keys': {'p256dh': subscription.p256dh, 'auth': subscription.auth},
        'created_at': subscription.created_at,
        'updated_at': subscription.updated_at,
    })


def send_web_push(subscription: dict, payload: dict) -> bool:
    """Send one push, returning False when delivery is not configured."""
    if not settings.vapid_private_key or not settings.vapid_subject or pywebpush is None:
        return False
    pywebpush(
        subscription_info=subscription,
        data=json.dumps(payload),
        vapid_private_key=settings.vapid_private_key,
        vapid_claims={'sub': settings.vapid_subject},
    )
    return True


def send_to_owner(db: Session, owner_id: uuid.UUID, payload: dict) -> int:
    """Deliver a payload to every subscription owned by the user."""
    if not settings.vapid_private_key or not settings.vapid_subject:
        return 0
    sent = 0
    for subscription in db.scalars(select(PushSubscription).where(PushSubscription.owner_id == owner_id)):
        send_web_push({'endpoint': subscription.endpoint, 'keys': {'p256dh': subscription.p256dh, 'auth': subscription.auth}}, payload)
        sent += 1
    return sent


def _owned(db: Session, owner_id: uuid.UUID, subscription_id: uuid.UUID):
    subscription = db.scalar(select(PushSubscription).where(
        PushSubscription.id == subscription_id,
        PushSubscription.owner_id == owner_id,
    ))
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
        if existing.owner_id != owner_id:
            raise HTTPException(409, 'Subscription endpoint already registered')
        existing.p256dh = body.keys.p256dh
        existing.auth = body.keys.auth
        db.commit()
        db.refresh(existing)
        return _out(existing)
    subscription = PushSubscription(owner_id=owner_id, endpoint=body.endpoint, p256dh=body.keys.p256dh, auth=body.keys.auth)
    db.add(subscription)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, 'Subscription endpoint already registered')
    db.refresh(subscription)
    return _out(subscription)


@router.get('/subscriptions/{subscription_id}', response_model=PushSubscriptionOut)
def get_subscription(subscription_id: uuid.UUID, identity=Depends(current_push_session), db: Session = Depends(get_db)):
    return _out(_owned(db, identity[1].id, subscription_id))


@router.patch('/subscriptions/{subscription_id}', response_model=PushSubscriptionOut)
def update_subscription(subscription_id: uuid.UUID, body: PushSubscriptionPatch, identity=Depends(current_push_session), db: Session = Depends(get_db)):
    subscription = _owned(db, identity[1].id, subscription_id)
    changes = body.model_dump(exclude_unset=True)
    if 'endpoint' in changes:
        conflict = db.scalar(select(PushSubscription).where(PushSubscription.endpoint == changes['endpoint'], PushSubscription.id != subscription.id))
        if conflict is not None:
            raise HTTPException(409, 'Subscription endpoint already registered')
        subscription.endpoint = changes['endpoint']
    if body.keys is not None:
        subscription.p256dh, subscription.auth = body.keys.p256dh, body.keys.auth
    db.commit()
    db.refresh(subscription)
    return _out(subscription)


@router.delete('/subscriptions/{subscription_id}', status_code=204)
def delete_subscription(subscription_id: uuid.UUID, identity=Depends(current_push_session), db: Session = Depends(get_db)):
    db.delete(_owned(db, identity[1].id, subscription_id))
    db.commit()
    return Response(status_code=204)

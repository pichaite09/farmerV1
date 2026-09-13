"""Synthetic-only recovery regressions; never invoke real push providers."""
import uuid
from datetime import datetime, timezone
from sqlalchemy import select
from app.database import SessionLocal
from app.models import Announcement
from test_admin_announcements import register, admin_headers

OLD = datetime(2000, 1, 1, tzinfo=timezone.utc)


def test_pre_activation_draft_cannot_be_sent(client):
    farmer, admin = register(client), register(client)
    auth = admin_headers(client, admin)
    body = {'title': 'Synthetic old draft', 'body': 'fixture', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    aid = client.post('/api/v1/admin/announcements', headers=auth, json=body).json()['id']
    with SessionLocal() as db:
        db.get(Announcement, uuid.UUID(aid)).created_at = OLD
        db.commit()
    response = client.post(f'/api/v1/admin/announcements/{aid}/send', headers=auth)
    assert response.status_code == 409
    with SessionLocal() as db:
        assert db.get(Announcement, uuid.UUID(aid)).status == 'draft'


import pytest
from sqlalchemy import func
from app.models import Notification, PushOutbox
from app.push import enqueue_push_outbox, claim_push_outbox, deliver_claimed


@pytest.mark.parametrize('old_field', ['campaign', 'notification'])
@pytest.mark.parametrize('status', ['pending', 'claimed', 'failed'])
def test_old_history_never_enqueued_claimed_or_delivered(client, monkeypatch, old_field, status):
    farmer, admin = register(client), register(client)
    auth = admin_headers(client, admin)
    farmer_auth = {'Authorization': 'Bearer ' + farmer['access_token']}
    subscription = {'endpoint': 'https://fcm.googleapis.com/synthetic-old', 'keys': {'p256dh': 'A' * 87, 'auth': 'B' * 22}}
    assert client.post('/api/v1/push/subscriptions', headers=farmer_auth, json=subscription).status_code == 201
    body = {'title': 'Synthetic history', 'body': 'fixture', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    aid = client.post('/api/v1/admin/announcements', headers=auth, json=body).json()['id']
    assert client.post(f'/api/v1/admin/announcements/{aid}/send', headers=auth).status_code == 200
    with SessionLocal() as db:
        announcement = db.get(Announcement, uuid.UUID(aid))
        notice = db.scalar(select(Notification))
        (announcement if old_field == 'campaign' else notice).created_at = OLD
        row = db.scalar(select(PushOutbox))
        row.status, row.claimed_at, row.next_attempt_at = status, OLD, OLD
        db.commit()
        before = (row.status, row.attempts, row.claimed_at, row.sent_at, row.last_error)
    # Device/subscription arrival must not reopen historical announcements.
    subscription['endpoint'] += '-new-device'
    assert client.post('/api/v1/push/subscriptions', headers=farmer_auth, json=subscription).status_code == 201
    assert client.post('/api/v1/devices/push-token', headers=farmer_auth, json={'token': 'fixture-no-replay-token-1234567890'}).status_code in (200, 201)
    calls = []
    monkeypatch.setattr('app.push.send_web_push', lambda *args: calls.append('web') or True)
    monkeypatch.setattr('app.fcm.send_fcm', lambda *args: calls.append('fcm'))
    with SessionLocal() as db:
        from app.push import send_to_owner
        notice = db.scalar(select(Notification))
        assert send_to_owner(db, uuid.UUID(farmer['user']['id']), {'notificationId': str(notice.id), 'title': 'fixture', 'body': 'fixture'}) == 0
        assert enqueue_push_outbox(db) == 0
        assert enqueue_push_outbox(db, owner_id=uuid.UUID(farmer['user']['id'])) == 0
        assert claim_push_outbox(db) == []
        row = db.scalar(select(PushOutbox))
        assert deliver_claimed(db, [row]) == (0, 0)  # defensive final provider gate
        db.expire_all()
        assert (row.status, row.attempts, row.claimed_at, row.sent_at, row.last_error) == before
        assert db.scalar(select(func.count()).select_from(PushOutbox)) == 1
        from app.scheduler import run_daily_once
        assert run_daily_once(db) == 0
    assert calls == []
    inbox = client.get('/api/v1/notifications', headers=farmer_auth)
    assert inbox.status_code == 200 and len(inbox.json()) == 1

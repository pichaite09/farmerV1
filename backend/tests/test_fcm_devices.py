import uuid
from unittest.mock import patch

from sqlalchemy import select

from app.models import Announcement, FcmDeviceToken, Notification, PushOutbox
from app.push import deliver_claimed, enqueue_push_outbox

PASSWORD = 'Testing-strong-password-42'


def auth(client, email):
    r = client.post('/api/v1/auth/register', json={'email': email, 'password': PASSWORD})
    return {'Authorization': 'Bearer ' + r.json()['access_token']}, r.json()['user']['id']


def test_register_update_delete_is_owner_scoped(client):
    a, _ = auth(client, f'{uuid.uuid4()}@example.com')
    b, _ = auth(client, f'{uuid.uuid4()}@example.com')
    assert client.post('/api/v1/devices/push-token', headers=a, json={'token': 'fcm-token-a-1234567890'}).status_code == 201
    updated = client.post('/api/v1/devices/push-token', headers=a, json={'token': 'fcm-token-a-1234567890'}).json()
    assert updated['token'] == 'fcm-token-a-1234567890'
    assert client.post('/api/v1/devices/push-token', headers=b, json={'token': 'fcm-token-a-1234567890'}).status_code == 409
    assert client.request('DELETE', '/api/v1/devices/push-token', headers=b, json={'token': 'fcm-token-a-1234567890'}).status_code == 404
    assert client.request('DELETE', '/api/v1/devices/push-token', headers=a, json={'token': 'fcm-token-a-1234567890'}).status_code == 204


def test_fcm_delivery_is_idempotent_and_suppresses_inactive(client):
    from app.database import SessionLocal
    db = SessionLocal()
    headers, user_id = auth(client, f'{uuid.uuid4()}@example.com')
    client.post('/api/v1/devices/push-token', headers=headers, json={'token': 'fcm-device-1234567890'})
    notification = Notification(owner_id=uuid.UUID(user_id), kind='admin_announcement', title='ประกาศ', body='เนื้อหา')
    announcement = Announcement(owner_id=uuid.UUID(user_id), target_type='role', target_role='farmer', title='ประกาศ', body='เนื้อหา', status='queued')
    db.add(announcement)
    db.flush()
    notification.announcement_id = announcement.id
    db.add(notification)
    db.commit()
    with patch('app.fcm.send_fcm', return_value='message-id') as send:
        assert enqueue_push_outbox(db, [notification]) == 1
        assert enqueue_push_outbox(db, [notification]) == 0
        rows = db.scalars(select(PushOutbox)).all()
        assert deliver_claimed(db, rows) == (1, 0)
        send.assert_called_once()

    assert client.request('DELETE', '/api/v1/devices/push-token', headers=headers, json={'token': 'fcm-device-1234567890'}).status_code == 204
    db.expire_all()
    device = db.scalar(select(FcmDeviceToken).where(FcmDeviceToken.token == 'fcm-device-1234567890'))
    assert device is not None
    assert device.active is False
    db.close()

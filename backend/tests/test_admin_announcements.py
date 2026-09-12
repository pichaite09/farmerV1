import uuid
import pytest
from sqlalchemy import select, text
from app.database import engine
from app.database import SessionLocal
from app.models import Announcement, AnnouncementRecipient, Notification, PushOutbox, User, Attachment
from app.push import MAX_ATTEMPTS, claim_push_outbox, deliver_claimed


def register(client, email=None):
    email = email or f'{uuid.uuid4()}@example.com'
    response = client.post('/api/v1/auth/register', json={'email': email, 'password': 'Testing-strong-password-42'})
    assert response.status_code == 201, response.text
    return response.json()


def admin_headers(client, user):
    with engine.begin() as conn:
        conn.execute(text("UPDATE users SET role='admin' WHERE id=:id"), {'id': user['user']['id']})
    response = client.post('/api/v1/auth/login', json={'email': user['user']['email'], 'password': 'Testing-strong-password-42'})
    assert response.status_code == 200
    return {'Authorization': 'Bearer ' + response.json()['access_token']}


def test_announcement_without_subscription_is_completed_and_in_inbox(client):
    farmer_a = register(client); farmer_b = register(client); admin = register(client)
    headers = admin_headers(client, admin)
    body = {'title': 'Water advisory', 'body': 'Water plots before noon.', 'targetType': 'selected', 'userIds': [farmer_a['user']['id']]}
    preview = client.post('/api/v1/admin/announcements/preview', headers=headers, json=body)
    assert preview.status_code == 200 and preview.json()['targetCount'] == 1
    created = client.post('/api/v1/admin/announcements', headers=headers, json=body)
    assert created.status_code == 201
    announcement_id = created.json()['id']
    sent = client.post(f'/api/v1/admin/announcements/{announcement_id}/send', headers=headers)
    assert sent.status_code == 200 and sent.json()['status'] == 'completed'
    assert client.get(f'/api/v1/admin/announcements/{announcement_id}', headers=headers).json()['status'] == 'completed'
    assert client.get(f'/api/v1/admin/announcements/{announcement_id}/delivery-summary', headers=headers).json()['status'] == 'completed'
    with SessionLocal() as db:
        assert db.scalar(select(Notification.id).where(Notification.announcement_id == uuid.UUID(announcement_id))) is not None
        assert db.scalar(select(PushOutbox.id).join(Notification, Notification.id == PushOutbox.notification_id).where(Notification.announcement_id == uuid.UUID(announcement_id))) is None
    inbox = client.get('/api/v1/notifications', headers={'Authorization': 'Bearer ' + farmer_a['access_token']})
    assert inbox.status_code == 200 and inbox.json()[0]['kind'] == 'admin_announcement'
    other = client.get('/api/v1/notifications', headers={'Authorization': 'Bearer ' + farmer_b['access_token']})
    assert other.status_code == 200 and other.json() == []
    assert client.get('/api/v1/admin/announcements', headers={'Authorization': 'Bearer ' + farmer_a['access_token']}).status_code == 403


def test_suspended_farmers_are_excluded_from_announcement_preview_and_send(client):
    active = register(client)
    suspended = register(client)
    admin = register(client)
    headers = admin_headers(client, admin)
    assert client.post(f"/api/v1/admin/users/{suspended['user']['id']}/suspend", headers=headers).status_code == 200
    body = {'title': 'Water advisory', 'body': 'Water plots before noon.', 'targetType': 'all'}
    preview = client.post('/api/v1/admin/announcements/preview', headers=headers, json=body)
    assert preview.status_code == 200 and preview.json()['targetCount'] == 1
    announcement = client.post('/api/v1/admin/announcements', headers=headers, json=body).json()
    sent = client.post(f"/api/v1/admin/announcements/{announcement['id']}/send", headers=headers)
    assert sent.status_code == 200 and sent.json()['targetCount'] == 1
    with SessionLocal() as db:
        recipients = db.scalars(select(AnnouncementRecipient).where(
            AnnouncementRecipient.announcement_id == uuid.UUID(announcement['id']),
        )).all()
        assert [recipient.user_id for recipient in recipients] == [uuid.UUID(active['user']['id'])]


def test_queued_announcement_is_suppressed_after_recipient_suspension(client, monkeypatch):
    farmer = register(client)
    admin = register(client)
    admin_auth = admin_headers(client, admin)
    subscription = {'endpoint': 'https://fcm.googleapis.com/suspended', 'keys': {'p256dh': 'A' * 87, 'auth': 'B' * 22}}
    assert client.post('/api/v1/push/subscriptions', headers={'Authorization': 'Bearer ' + farmer['access_token']}, json=subscription).status_code == 201
    body = {'title': 'x', 'body': 'y', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    announcement = client.post('/api/v1/admin/announcements', headers=admin_auth, json=body).json()
    assert client.post(f"/api/v1/admin/announcements/{announcement['id']}/send", headers=admin_auth).json()['status'] == 'queued'
    assert client.post(f"/api/v1/admin/users/{farmer['user']['id']}/suspend", headers=admin_auth).status_code == 200
    calls = []
    monkeypatch.setattr('app.push.send_web_push', lambda subscription, payload: calls.append(subscription) or True)
    with SessionLocal() as db:
        claimed = claim_push_outbox(db)
        assert len(claimed) == 1
        assert deliver_claimed(db, claimed) == (0, 1)
        row = db.scalar(select(PushOutbox).where(PushOutbox.id == claimed[0].id))
        recipient = db.scalar(select(AnnouncementRecipient).where(AnnouncementRecipient.announcement_id == uuid.UUID(announcement['id'])))
        assert row.status == 'failed' and row.last_error == 'suppressed'
        assert recipient.status == 'suppressed'
        assert db.get(User, uuid.UUID(farmer['user']['id'])).status == 'suspended'
    assert calls == []


def test_announcement_cancel_suppresses_inbox_and_is_owner_scoped(client):
    farmer = register(client); admin_a = register(client); admin_b = register(client)
    headers_a = admin_headers(client, admin_a)
    headers_b = admin_headers(client, admin_b)
    body = {'title': 'Cancelled', 'body': 'Do not show', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    created = client.post('/api/v1/admin/announcements', headers=headers_a, json=body).json()
    aid = created['id']
    assert client.get(f'/api/v1/admin/announcements/{aid}', headers=headers_b).status_code == 404
    cancelled = client.post(f'/api/v1/admin/announcements/{aid}/cancel', headers=headers_a)
    assert cancelled.status_code == 200 and cancelled.json()['status'] == 'cancelled'
    assert client.get('/api/v1/notifications', headers={'Authorization': 'Bearer ' + farmer['access_token']}).json() == []


def test_announcement_targeting_rejects_admins(client):
    farmer = register(client); admin = register(client)
    headers = admin_headers(client, admin)
    selected = {'title': 'x', 'body': 'y', 'targetType': 'selected', 'userIds': [admin['user']['id']]}
    assert client.post('/api/v1/admin/announcements/preview', headers=headers, json=selected).status_code == 422
    role = {'title': 'x', 'body': 'y', 'targetType': 'role', 'role': 'admin'}
    assert client.post('/api/v1/admin/announcements', headers=headers, json=role).status_code == 422


def test_announcement_send_rolls_back_when_outbox_enqueue_fails(client, monkeypatch):
    farmer = register(client); admin = register(client)
    headers = admin_headers(client, admin)
    body = {'title': 'x', 'body': 'y', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    aid = client.post('/api/v1/admin/announcements', headers=headers, json=body).json()['id']
    monkeypatch.setattr('app.admin.enqueue_push_outbox', lambda *args, **kwargs: (_ for _ in ()).throw(RuntimeError('enqueue down')))
    with pytest.raises(RuntimeError, match='enqueue down'):
        client.post(f'/api/v1/admin/announcements/{aid}/send', headers=headers)
    with SessionLocal() as db:
        announcement = db.get(Announcement, uuid.UUID(aid))
        assert announcement.status == 'draft'
        assert db.scalar(select(AnnouncementRecipient.id).where(AnnouncementRecipient.announcement_id == announcement.id)) is None
        assert db.scalar(select(Notification.id).where(Notification.announcement_id == announcement.id)) is None
        assert db.scalar(select(PushOutbox.id).join(Notification, Notification.id == PushOutbox.notification_id).where(Notification.announcement_id == announcement.id)) is None


def test_announcement_with_subscription_creates_one_claimable_outbox(client, monkeypatch):
    farmer = register(client); admin = register(client)
    headers = admin_headers(client, admin)
    subscription = {'endpoint': 'https://fcm.googleapis.com/announcement', 'keys': {'p256dh': 'A' * 87, 'auth': 'B' * 22}}
    assert client.post('/api/v1/push/subscriptions', headers={'Authorization': 'Bearer ' + farmer['access_token']}, json=subscription).status_code == 201
    body = {'title': 'x', 'body': 'y', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    aid = client.post('/api/v1/admin/announcements', headers=headers, json=body).json()['id']
    sent = client.post(f'/api/v1/admin/announcements/{aid}/send', headers=headers)
    assert sent.status_code == 200 and sent.json()['status'] == 'queued'
    with SessionLocal() as db:
        announcement = db.get(Announcement, uuid.UUID(aid))
        outbox = db.scalars(select(PushOutbox).join(Notification, Notification.id == PushOutbox.notification_id).where(Notification.announcement_id == uuid.UUID(aid))).all()
        assert announcement.status == 'queued'
        assert len(outbox) == 1 and outbox[0].status == 'pending'
    monkeypatch.setattr('app.push.send_web_push', lambda subscription, payload: True)
    with SessionLocal() as db:
        claimed = claim_push_outbox(db)
        assert len(claimed) == 1
        announcement = db.get(Announcement, uuid.UUID(aid))
        assert announcement.status == 'sending'
        deliver_claimed(db, claimed)
        announcement = db.get(Announcement, uuid.UUID(aid))
        recipient = db.scalar(select(AnnouncementRecipient).where(AnnouncementRecipient.announcement_id == announcement.id))
        assert announcement.status == 'sent' and announcement.sent_at is not None
        assert recipient.status == 'sent'


def test_mixed_subscription_recipients_complete_as_sent_after_active_delivery(client, monkeypatch):
    subscribed = register(client)
    no_subscription = register(client)
    admin = register(client)
    headers = admin_headers(client, admin)
    subscription = {'endpoint': 'https://fcm.googleapis.com/mixed', 'keys': {'p256dh': 'A' * 87, 'auth': 'B' * 22}}
    assert client.post('/api/v1/push/subscriptions', headers={'Authorization': 'Bearer ' + subscribed['access_token']}, json=subscription).status_code == 201
    body = {'title': 'x', 'body': 'y', 'targetType': 'selected', 'userIds': [subscribed['user']['id'], no_subscription['user']['id']]}
    aid = client.post('/api/v1/admin/announcements', headers=headers, json=body).json()['id']
    queued = client.post(f'/api/v1/admin/announcements/{aid}/send', headers=headers)
    assert queued.status_code == 200 and queued.json()['status'] == 'queued'
    monkeypatch.setattr('app.push.send_web_push', lambda subscription, payload: True)
    with SessionLocal() as db:
        claimed = claim_push_outbox(db)
        assert len(claimed) == 1
        assert db.get(Announcement, uuid.UUID(aid)).status == 'sending'
        assert deliver_claimed(db, claimed) == (1, 0)
        announcement = db.get(Announcement, uuid.UUID(aid))
        recipients = db.scalars(select(AnnouncementRecipient).where(AnnouncementRecipient.announcement_id == announcement.id)).all()
        assert announcement.status == 'sent'
        assert {recipient.status for recipient in recipients} == {'sent', 'suppressed'}
    assert client.get(f'/api/v1/admin/announcements/{aid}', headers=headers).json()['status'] == 'sent'


def test_multi_subscription_failure_does_not_finalize_recipient_or_announcement(client, monkeypatch):
    farmer = register(client)
    admin = register(client)
    admin_auth = admin_headers(client, admin)
    farmer_auth = {'Authorization': 'Bearer ' + farmer['access_token']}
    for endpoint in ('https://fcm.googleapis.com/first', 'https://fcm.googleapis.com/second'):
        subscription = {'endpoint': endpoint, 'keys': {'p256dh': 'A' * 87, 'auth': 'B' * 22}}
        assert client.post('/api/v1/push/subscriptions', headers=farmer_auth, json=subscription).status_code == 201

    body = {'title': 'x', 'body': 'y', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    aid = client.post('/api/v1/admin/announcements', headers=admin_auth, json=body).json()['id']
    assert client.post(f'/api/v1/admin/announcements/{aid}/send', headers=admin_auth).json()['status'] == 'queued'

    with SessionLocal() as db:
        claimed = claim_push_outbox(db, limit=10)
        assert len(claimed) == 2
        failing, remaining = claimed
        failing.attempts = MAX_ATTEMPTS
        monkeypatch.setattr('app.push.send_web_push', lambda subscription, payload: (_ for _ in ()).throw(RuntimeError('provider down')))
        assert deliver_claimed(db, [failing]) == (0, 1)
        recipient = db.scalar(select(AnnouncementRecipient).where(AnnouncementRecipient.announcement_id == uuid.UUID(aid)))
        announcement = db.get(Announcement, uuid.UUID(aid))
        assert recipient.status == 'pending'
        assert announcement.status == 'sending'

        monkeypatch.setattr('app.push.send_web_push', lambda subscription, payload: True)
        assert deliver_claimed(db, [remaining]) == (1, 0)
        recipient = db.scalar(select(AnnouncementRecipient).where(AnnouncementRecipient.announcement_id == uuid.UUID(aid)))
        announcement = db.get(Announcement, uuid.UUID(aid))
        assert recipient.status == 'sent'
        assert announcement.status == 'sent'



def test_announcement_image_is_private_metadata_and_farmer_owner_scoped(client):
    farmer = register(client); other = register(client); admin = register(client)
    admin_auth = admin_headers(client, admin)
    farmer_auth = {'Authorization': 'Bearer ' + farmer['access_token']}
    other_auth = {'Authorization': 'Bearer ' + other['access_token']}
    body = {'title': 'รูปภาพ', 'body': 'รายละเอียด', 'type': 'urgent', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    announcement = client.post('/api/v1/admin/announcements', headers=admin_auth, json=body)
    assert announcement.status_code == 201, announcement.text
    image = client.post(f"/api/v1/admin/announcements/{announcement.json()['id']}/image", headers=admin_auth, files={'file': ('notice.png', b'\x89PNG\r\n\x1a\n' + b'0' * 20, 'image/png')})
    assert image.status_code == 201, image.text
    assert image.json()['contentType'] == 'image/png'
    assert 'contentUrl' not in image.json()
    sent = client.post(f"/api/v1/admin/announcements/{announcement.json()['id']}/send", headers=admin_auth)
    assert sent.status_code == 200
    notification = client.get('/api/v1/notifications', headers=farmer_auth)
    assert notification.json()[0]['announcementImageId'] == image.json()['id']
    content = client.get(f"/api/v1/notifications/{notification.json()[0]['id']}/image", headers=farmer_auth)
    assert content.status_code == 200 and content.headers['content-type'].startswith('image/png')
    assert client.get(f"/api/v1/notifications/{notification.json()[0]['id']}/image", headers=other_auth).status_code == 404
    with SessionLocal() as db:
        attachment = db.get(Attachment, uuid.UUID(image.json()['id']))
        assert attachment.parent_type == 'announcement' and attachment.owner_id == uuid.UUID(admin['user']['id'])


def test_fcm_announcement_payload_carries_private_image_id(client):
    farmer = register(client); admin = register(client)
    admin_auth = admin_headers(client, admin)
    farmer_auth = {'Authorization': 'Bearer ' + farmer['access_token']}
    token = client.post('/api/v1/devices/push-token', headers=farmer_auth, json={'token': 'fixture-fcm-token-1234567890'})
    assert token.status_code in (201, 200), token.text
    body = {'title': 'ประกาศ', 'body': 'ข้อความ', 'type': 'info', 'targetType': 'selected', 'userIds': [farmer['user']['id']]}
    aid = client.post('/api/v1/admin/announcements', headers=admin_auth, json=body).json()['id']
    image = client.post(f'/api/v1/admin/announcements/{aid}/image', headers=admin_auth, files={'file': ('a.jpg', b'\xff\xd8\xff' + b'0' * 20, 'image/jpeg')})
    assert image.status_code == 201, image.text
    sent = client.post(f'/api/v1/admin/announcements/{aid}/send', headers=admin_auth)
    assert sent.status_code == 200
    with SessionLocal() as db:
        outbox = db.scalar(select(PushOutbox).join(Notification, Notification.id == PushOutbox.notification_id).where(Notification.announcement_id == uuid.UUID(aid)))
        assert outbox.payload['announcementImageId'] == image.json()['id']

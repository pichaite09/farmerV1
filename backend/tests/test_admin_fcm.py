import uuid

from sqlalchemy import text

from app.database import SessionLocal, engine
from app.models import FcmDeviceToken
from test_admin import _admin_headers, _register


PATH = '/api/v1/admin/users/{}/test-notification'


def _seed_token(user_id, *, active=True):
    with SessionLocal() as db:
        row = FcmDeviceToken(owner_id=user_id, token='fixture-' + uuid.uuid4().hex, active=active)
        db.add(row)
        db.commit()
        return str(row.id)


def test_test_notification_requires_admin_and_farmer_is_forbidden(client):
    farmer = _register(client)
    response = client.post(PATH.format(farmer['user']['id']), headers={
        'Authorization': 'Bearer ' + farmer['access_token'],
    }, json={'title': 'ทดสอบ', 'body': 'ข้อความ'})
    assert response.status_code == 403


def test_test_notification_requires_active_target(client, monkeypatch):
    farmer = _register(client)
    admin = _register(client)
    headers = _admin_headers(client, admin)
    with engine.begin() as conn:
        conn.execute(text("UPDATE users SET status='suspended' WHERE id=:id"), {'id': farmer['user']['id']})
    monkeypatch.setattr('app.admin.send_fcm', lambda *args: (_ for _ in ()).throw(AssertionError('must not send')))

    response = client.post(PATH.format(farmer['user']['id']), headers=headers,
                           json={'title': 'ทดสอบ', 'body': 'ข้อความ'})
    assert response.status_code == 409
    assert response.json()['message'] == 'Target user is not active'


def test_test_notification_reports_no_active_tokens(client):
    farmer = _register(client)
    admin = _register(client)
    response = client.post(PATH.format(farmer['user']['id']), headers=_admin_headers(client, admin),
                           json={'title': 'ทดสอบ', 'body': 'ข้อความ'})
    assert response.status_code == 422
    assert response.json()['message'] == 'Target user has no active device tokens'


def test_test_notification_sends_only_active_tokens_and_returns_count(client, monkeypatch):
    farmer = _register(client)
    admin = _register(client)
    active_id = _seed_token(farmer['user']['id'])
    _seed_token(farmer['user']['id'], active=False)
    calls = []
    monkeypatch.setattr('app.admin.send_fcm', lambda token, payload: calls.append(payload))

    response = client.post(PATH.format(farmer['user']['id']), headers=_admin_headers(client, admin),
                           json={'title': '  ทดสอบ  ', 'body': '  ข้อความ  '})
    assert response.status_code == 200, response.text
    data = response.json()
    assert data['attempted'] == data['sent'] == 1
    assert data['failed'] == 0
    assert data['results'] == [{'deviceId': active_id, 'status': 'sent'}]
    assert calls == [{'title': 'ทดสอบ', 'body': 'ข้อความ', 'kind': 'admin_test'}]
    assert 'fixture-' not in response.text


def test_test_notification_provider_failure_is_safe_and_counted(client, monkeypatch):
    farmer = _register(client)
    admin = _register(client)
    _seed_token(farmer['user']['id'])
    monkeypatch.setattr('app.admin.send_fcm', lambda *args: (_ for _ in ()).throw(RuntimeError('private provider detail')))

    response = client.post(PATH.format(farmer['user']['id']), headers=_admin_headers(client, admin),
                           json={'title': 'ทดสอบ', 'body': 'ข้อความ'})
    assert response.status_code == 502
    data = response.json()
    assert data['code'] == 'request_error'
    assert 'fcm_provider_failure' in data['message']
    assert 'private provider detail' not in response.text
    assert 'fixture-' not in response.text
    assert 'token' not in response.text.lower()


def test_test_notification_validates_title_and_body(client):
    farmer = _register(client)
    admin = _register(client)
    headers = _admin_headers(client, admin)
    for body in ({'title': ' ', 'body': 'ok'}, {'title': 'ok', 'body': ' '}, {'title': 'x' * 201, 'body': 'ok'}):
        response = client.post(PATH.format(farmer['user']['id']), headers=headers, json=body)
        assert response.status_code == 422

import uuid
import threading
import pytest
from sqlalchemy.exc import DBAPIError, IntegrityError
from sqlalchemy import text
from app.database import engine, SessionLocal
from app.models import AuditLog, AuthSession, User
from app.admin import _guard_admin_count
from fastapi import HTTPException
from test_admin import _register, _admin_headers


def test_admin_user_management_and_audit_redacts_secrets(client):
    farmer = _register(client)
    admin = _register(client)
    headers = _admin_headers(client, admin)
    uid = farmer['user']['id']
    assert client.get('/api/v1/admin/users', headers=headers).json()['total'] == 2
    assert client.get('/api/v1/admin/users/' + uid, headers=headers).json()['email'] == farmer['user']['email']
    changed = client.patch('/api/v1/admin/users/' + uid, headers=headers, json={'firstName': 'Ada', 'role': 'admin', 'password': 'nope'})
    assert changed.status_code == 422
    changed = client.patch('/api/v1/admin/users/' + uid, headers=headers, json={'firstName': 'Ada', 'role': 'admin'})
    assert changed.status_code == 200 and changed.json()['role'] == 'admin'
    assert 'passwordHash' not in changed.text
    assert client.post('/api/v1/admin/users/' + uid + '/suspend', headers=headers).status_code == 200
    assert client.post('/api/v1/auth/login', json={'email': farmer['user']['email'], 'password': 'Testing-strong-password-42'}).status_code == 401
    logs = client.get('/api/v1/admin/audit-logs?targetType=user&limit=2', headers=headers)
    assert logs.status_code == 200 and logs.json()['total'] >= 2
    assert 'password' not in logs.text.lower() and 'token' not in logs.text.lower()


def test_farmer_denied_and_last_admin_protected(client):
    farmer = _register(client)
    admin = _register(client)
    assert client.get('/api/v1/admin/users', headers={'Authorization': 'Bearer ' + farmer['access_token']}).status_code == 403
    headers = _admin_headers(client, admin)
    assert client.patch('/api/v1/admin/users/' + admin['user']['id'], headers=headers, json={'role': 'farmer'}).status_code == 409
    assert client.post('/api/v1/admin/users/' + admin['user']['id'] + '/suspend', headers=headers).status_code == 409


def test_admin_user_list_filters_and_revoke_sessions(client):
    farmer = _register(client)
    admin = _register(client)
    headers = _admin_headers(client, admin)
    assert client.get('/api/v1/admin/users?role=farmer&limit=1&offset=0', headers=headers).json()['total'] == 1
    assert client.get('/api/v1/admin/users?status=active&limit=0', headers=headers).status_code == 422
    assert client.post('/api/v1/admin/users/' + farmer['user']['id'] + '/revoke-sessions', headers=headers).json()['revoked'] >= 1


def test_suspension_revokes_old_token_and_activation_does_not_revive_it(client):
    farmer = _register(client)
    admin = _register(client)
    headers = _admin_headers(client, admin)
    farmer_headers = {'Authorization': 'Bearer ' + farmer['access_token']}

    assert client.post('/api/v1/admin/users/' + farmer['user']['id'] + '/suspend', headers=headers).status_code == 200
    assert client.get('/api/v1/auth/me', headers=farmer_headers).status_code == 401
    assert client.post('/api/v1/admin/users/' + farmer['user']['id'] + '/activate', headers=headers).status_code == 200
    assert client.get('/api/v1/auth/me', headers=farmer_headers).status_code == 401
    login = client.post('/api/v1/auth/login', json={
        'email': farmer['user']['email'], 'password': 'Testing-strong-password-42',
    })
    assert login.status_code == 200


def test_audit_log_is_immutable_and_actor_cannot_be_deleted(client):
    farmer = _register(client)
    admin = _register(client)
    headers = _admin_headers(client, admin)
    assert client.patch('/api/v1/admin/users/' + farmer['user']['id'], headers=headers, json={'firstName': 'Ada'}).status_code == 200

    with pytest.raises(DBAPIError):
        with engine.begin() as conn:
            conn.execute(text("UPDATE audit_logs SET action='tampered'"))
    with pytest.raises(DBAPIError):
        with engine.begin() as conn:
            conn.execute(text('DELETE FROM audit_logs'))
    with pytest.raises(IntegrityError):
        with engine.begin() as conn:
            conn.execute(text('DELETE FROM users WHERE id = :id'), {'id': admin['user']['id']})


def test_concurrent_last_admin_transitions_are_serialized(client):
    first = _register(client)
    second = _register(client)
    _admin_headers(client, first)
    _admin_headers(client, second)
    locked = threading.Event()
    release = threading.Event()
    result = {}

    def demote_first():
        with SessionLocal() as db:
            user = db.get(User, first['user']['id'])
            _guard_admin_count(db, user, new_role='farmer')
            locked.set()
            release.wait(timeout=5)
            user.role = 'farmer'
            db.commit()

    def demote_second():
        locked.wait(timeout=5)
        with SessionLocal() as db:
            user = db.get(User, second['user']['id'])
            try:
                _guard_admin_count(db, user, new_role='farmer')
            except HTTPException as exc:
                result['status'] = exc.status_code
            finally:
                db.rollback()

    first_thread = threading.Thread(target=demote_first)
    second_thread = threading.Thread(target=demote_second)
    first_thread.start()
    second_thread.start()
    assert locked.wait(timeout=5)
    release.set()
    first_thread.join(timeout=5)
    second_thread.join(timeout=5)
    assert not first_thread.is_alive() and not second_thread.is_alive()
    assert result['status'] == 409

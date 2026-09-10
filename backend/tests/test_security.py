import uuid
import time
import jwt
import pytest
from concurrent.futures import ThreadPoolExecutor
from sqlalchemy import text
from app.database import engine, settings
from app.throttle import throttle
from types import SimpleNamespace


def registered(client):
    r = client.post('/api/v1/auth/register', json={'email': f'{uuid.uuid4()}@example.com', 'password': 'Testing-strong-password-42'})
    assert r.status_code == 201
    return r.json()

@pytest.mark.parametrize('case', ['expired', 'future', 'signature', 'algorithm', 'issuer', 'audience', 'missing', 'unknown_session', 'owner_mismatch'])
def test_invalid_signed_tokens(client, case):
    a = registered(client)
    b = registered(client)
    claims = jwt.decode(a['access_token'], settings.jwt_secret, algorithms=['HS256'], audience='farmer-main-api')
    key, algorithm = settings.jwt_secret, 'HS256'
    if case == 'expired': claims['exp'] = int(time.time()) - 1
    if case == 'future': claims['iat'] = int(time.time()) + 3600
    if case == 'signature': key = 'wrong-secret-' * 8
    if case == 'algorithm': algorithm = 'HS384'
    if case == 'issuer': claims['iss'] = 'other-app'
    if case == 'audience': claims['aud'] = 'other-app'
    if case == 'missing': del claims['exp']
    if case == 'unknown_session': claims['jti'] = str(uuid.uuid4())
    if case == 'owner_mismatch': claims['sub'] = b['user']['id']
    token = jwt.encode(claims, key, algorithm=algorithm)
    assert client.get('/api/v1/auth/me', headers={'Authorization': 'Bearer '+token}).status_code == 401
    assert client.get('/api/v1/auth/me', headers={'Authorization': 'Bearer '+b['access_token']}).json() == b['user']


def test_persistent_atomic_throttle():
    request = SimpleNamespace(client=SimpleNamespace(host='security-test'))
    def attempt(_):
        try:
            throttle(request, 'concurrent@example.com')
            return 200
        except Exception as exc:
            return exc.status_code
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(attempt, range(14)))
    assert results.count(200) == settings.auth_rate_limit
    assert results.count(429) == 14 - settings.auth_rate_limit
    engine.dispose()
    assert attempt(0) == 429
    with engine.connect() as conn:
        assert conn.execute(text('SELECT min(attempts) FROM auth_throttles')).scalar_one() == 15


def test_forwarded_header_does_not_reset_limit(client):
    for i in range(settings.auth_rate_limit + 1):
        r = client.post('/api/v1/auth/login', headers={'X-Forwarded-For': f'10.2.1.{i}'}, json={'email': f'missing{i}@example.com', 'password': 'Testing-password-42'})
        assert r.status_code == (401 if i < settings.auth_rate_limit else 429)


def test_cors_and_health(client):
    assert client.get('/health/ready').json() == {'status': 'ok', 'database': 'ok'}
    for origin, expected in [(settings.cors_origins[0], 200), ('https://evil.example', 400)]:
        r = client.options('/api/v1/auth/me', headers={'Origin': origin, 'Access-Control-Request-Method': 'GET', 'Access-Control-Request-Headers': 'authorization'})
        assert r.status_code == expected
        if expected == 200: assert r.headers['access-control-allow-origin'] == origin

@pytest.mark.parametrize('key', ['DATABASE_URL', 'JWT_SECRET', 'CORS_ORIGINS'])
def test_each_required_config(monkeypatch, key):
    from app.config import Settings
    monkeypatch.delenv(key, raising=False)
    with pytest.raises(ValueError): Settings(_env_file=None)


def test_database_forbids_admin(client):
    from sqlalchemy.exc import IntegrityError
    a = registered(client)
    with pytest.raises(IntegrityError):
        with engine.begin() as conn:
            conn.execute(text("UPDATE users SET role='admin' WHERE id=:id"), {'id': a['user']['id']})

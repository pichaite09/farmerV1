import uuid
import pytest

PASSWORD = 'Test-only-strong-pass-42'

def test_login_me_logout_session_isolation(client):
    email = f'phase1-{uuid.uuid4()}@example.com'
    register = client.post('/api/v1/auth/register', json={'email': email, 'password': PASSWORD})
    assert register.status_code == 201
    login = client.post('/api/v1/auth/login', json={'email': email, 'password': PASSWORD})
    assert login.status_code == 200, login.text
    a, b = register.json(), login.json()
    assert a['user'] == b['user']
    h1 = {'Authorization': 'Bearer ' + a['access_token']}
    h2 = {'Authorization': 'Bearer ' + b['access_token']}
    assert client.get('/api/v1/auth/me', headers=h1).json() == a['user']
    assert client.post('/api/v1/auth/logout', headers=h1).status_code == 204
    assert client.get('/api/v1/auth/me', headers=h1).status_code == 401
    assert client.post('/api/v1/auth/logout', headers=h1).status_code == 401
    assert client.get('/api/v1/auth/me', headers=h2).json() == b['user']

@pytest.mark.parametrize('header', [None, '', 'Bearer', 'Bearer malformed', 'Basic abc', 'Bearer a.b.c', 'Bearer null'])
def test_missing_and_malformed_auth(client, header):
    headers = {} if header is None else {'Authorization': header}
    for method, path in [('get', '/api/v1/auth/me'), ('post', '/api/v1/auth/logout')]:
        r = getattr(client, method)(path, headers=headers)
        assert r.status_code == 401
        assert set(r.json()) == {'code', 'message', 'fieldErrors', 'requestId'}
        assert r.headers['www-authenticate'] == 'Bearer'

def test_duplicate_and_invalid_credentials(client):
    body = {'email': 'phase1-duplicate@example.com', 'password': PASSWORD}
    assert client.post('/api/v1/auth/register', json=body).status_code == 201
    body['email'] = body['email'].upper()
    r = client.post('/api/v1/auth/register', json=body)
    assert r.status_code == 409
    assert set(r.json()) == {'code', 'message', 'fieldErrors', 'requestId'}
    body['password'] = 'Wrong-password-42'
    assert client.post('/api/v1/auth/login', json=body).status_code == 401
    body['email'] = 'phase1-unknown@example.com'
    assert client.post('/api/v1/auth/login', json=body).status_code == 401

@pytest.mark.parametrize('extra', [{'role': 'admin'}, {'ownerUserId': str(uuid.uuid4())}, {'owner_user_id': str(uuid.uuid4())}])
def test_self_escalation_rejected(client, extra):
    for route in ('register', 'login'):
        r = client.post('/api/v1/auth/' + route, json={'email': 'phase1-inject@example.com', 'password': PASSWORD, **extra})
        assert r.status_code == 422
        assert set(r.json()) == {'code', 'message', 'fieldErrors', 'requestId'}
        assert PASSWORD not in r.text

@pytest.mark.parametrize('email,password', [('bad', PASSWORD), ('phase1@example.com', 'short'), ('phase1@example.com', 'x'*201)])
def test_validation(client, email, password):
    assert client.post('/api/v1/auth/register', json={'email': email, 'password': password}).status_code == 422

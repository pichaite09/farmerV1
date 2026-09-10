import importlib
import uuid


def test_registration_persists_farmer_with_argon2():
    assert importlib.util.find_spec('app.main') is not None, 'auth API missing'
    from fastapi.testclient import TestClient
    from app.main import app
    from app.database import engine
    from sqlalchemy import text
    email = f'phase1-{uuid.uuid4()}@example.com'
    with TestClient(app) as client:
        response = client.post('/api/v1/auth/register', json={'email': email.upper(), 'password': 'Test-only-strong-pass-42'})
        assert response.status_code == 201, response.text
        data = response.json()
        assert data['token_type'] == 'bearer'
        assert data['user']['email'] == email
        assert data['user']['role'] == 'farmer'
        with engine.connect() as conn:
            row = conn.execute(text('SELECT password_hash, role FROM users WHERE email=:email'), {'email': email}).one()
            assert row.password_hash.startswith('$argon2id$')
            assert row.role == 'farmer'

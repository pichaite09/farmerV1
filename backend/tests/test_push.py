from test_phase2_resources import register


SUBSCRIPTION = {
    "endpoint": "https://push.example.test/subscription/one",
    "keys": {"p256dh": "p256dh-value", "auth": "auth-value"},
}


def test_vapid_public_key_requires_authentication(client):
    response = client.get('/api/v1/push/vapid-public-key')
    assert response.status_code == 401


def test_vapid_public_key_is_public_only(client, monkeypatch):
    owner = register(client, 'push-key@example.com')
    monkeypatch.setattr('app.push.settings.vapid_public_key', 'public-key')
    monkeypatch.setattr('app.push.settings.vapid_private_key', 'private-key')

    response = client.get('/api/v1/push/vapid-public-key', headers=owner)

    assert response.status_code == 200
    assert response.json() == {'publicKey': 'public-key'}
    assert 'private' not in response.text.lower()


def test_subscription_can_be_registered_updated_and_deleted_by_owner(client):
    owner = register(client, 'push-owner@example.com')
    other = register(client, 'push-other@example.com')

    created = client.post('/api/v1/push/subscriptions', headers=owner, json=SUBSCRIPTION)
    assert created.status_code == 201, created.text
    subscription_id = created.json()['id']
    assert created.json()['endpoint'] == SUBSCRIPTION['endpoint']
    assert created.json()['keys'] == SUBSCRIPTION['keys']

    updated = client.patch(
        f'/api/v1/push/subscriptions/{subscription_id}',
        headers=owner,
        json={'keys': {'p256dh': 'new-p256dh', 'auth': 'new-auth'}},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()['keys'] == {'p256dh': 'new-p256dh', 'auth': 'new-auth'}

    assert client.get(f'/api/v1/push/subscriptions/{subscription_id}', headers=other).status_code == 404
    assert client.delete(f'/api/v1/push/subscriptions/{subscription_id}', headers=other).status_code == 404
    assert client.delete(f'/api/v1/push/subscriptions/{subscription_id}', headers=owner).status_code == 204
    assert client.get(f'/api/v1/push/subscriptions/{subscription_id}', headers=owner).status_code == 404


def test_same_endpoint_cannot_be_taken_by_another_owner(client):
    owner = register(client, 'push-first@example.com')
    other = register(client, 'push-second@example.com')
    assert client.post('/api/v1/push/subscriptions', headers=owner, json=SUBSCRIPTION).status_code == 201

    response = client.post('/api/v1/push/subscriptions', headers=other, json=SUBSCRIPTION)

    assert response.status_code == 409


def test_send_web_push_is_disabled_without_private_configuration(monkeypatch):
    from app.push import send_web_push

    monkeypatch.setattr('app.push.settings.vapid_private_key', None)
    monkeypatch.setattr('app.push.settings.vapid_subject', None)
    called = []
    monkeypatch.setattr('app.push.pywebpush', lambda **kwargs: called.append(kwargs))

    assert send_web_push(SUBSCRIPTION, {'title': 'hello'}) is False
    assert called == []


def test_send_web_push_uses_configured_vapid_without_logging_private_key(monkeypatch, caplog):
    from app.push import send_web_push

    monkeypatch.setattr('app.push.settings.vapid_private_key', 'private-secret')
    monkeypatch.setattr('app.push.settings.vapid_subject', 'mailto:farmer@example.com')
    calls = []
    monkeypatch.setattr('app.push.pywebpush', lambda **kwargs: calls.append(kwargs))

    assert send_web_push(SUBSCRIPTION, {'title': 'hello'}) is True
    assert calls[0]['vapid_private_key'] == 'private-secret'
    assert calls[0]['vapid_claims'] == {'sub': 'mailto:farmer@example.com'}
    assert 'private-secret' not in caplog.text

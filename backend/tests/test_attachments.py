import io
import uuid

PASSWORD = 'Phase5-strong-password-42'
JPEG = b'\xff\xd8\xff\xe0phase5'
PNG = b'\x89PNG\r\n\x1a\nphase5'
WEBP = b'RIFF\x04\x00\x00\x00WEBP'


def register(client, email):
    response = client.post('/api/v1/auth/register', json={'email': email, 'password': PASSWORD})
    assert response.status_code == 201, response.text
    return {'Authorization': 'Bearer ' + response.json()['access_token']}


def make_activity_parent(client, headers):
    plot = client.post('/api/v1/plots', headers=headers, json={'name': 'Phase 5', 'area': 1, 'soil': 'loam'}).json()
    cycle = client.post('/api/v1/cycles', headers=headers, json={
        'name': 'Rice', 'plotId': plot['id'], 'cropType': 'rice', 'variety': 'พื้นเมือง',
        'plantingMethod': 'direct', 'startDate': '2026-09-01',
    }).json()
    activity = client.post('/api/v1/activities', headers=headers, json={
        'cycleId': cycle['id'], 'type': 'plant', 'date': '2026-09-02',
    }).json()
    return plot, activity


def upload(client, headers, parent_type, parent_id, data=JPEG, filename='field.jpg'):
    return client.post('/api/v1/attachments', headers=headers, data={
        'parentType': parent_type, 'parentId': parent_id,
    }, files={'file': (filename, io.BytesIO(data), 'image/jpeg')})


def test_attachments_upload_list_content_replace_delete_and_owner_isolation(client, tmp_path, monkeypatch):
    from app.database import settings
    monkeypatch.setattr(settings, 'attachment_storage_path', str(tmp_path))
    a = register(client, 'phase5-a@example.com')
    b = register(client, 'phase5-b@example.com')
    plot, activity = make_activity_parent(client, a)

    first = upload(client, a, 'plot', plot['id'])
    assert first.status_code == 201, first.text
    attachment = first.json()
    assert attachment['parentType'] == 'plot'
    assert attachment['contentUrl'].endswith(f"/attachments/{attachment['id']}/content")
    assert client.get(f"/api/v1/attachments/{attachment['id']}/content", headers=a).content == JPEG
    assert client.get(f"/api/v1/attachments/{attachment['id']}/content", headers=b).status_code == 404
    assert client.get('/api/v1/attachments', headers=b, params={'parentType': 'plot', 'parentId': plot['id']}).status_code == 404

    replacement = upload(client, a, 'plot', plot['id'], PNG, 'field.png')
    assert replacement.status_code == 201, replacement.text
    assert replacement.json()['id'] == attachment['id']
    assert client.get(f"/api/v1/attachments/{attachment['id']}/content", headers=a).content == PNG
    assert len(client.get('/api/v1/attachments', headers=a, params={'parentType': 'plot', 'parentId': plot['id']}).json()) == 1

    activity_upload = upload(client, a, 'activity', activity['id'], WEBP, 'field.webp')
    assert activity_upload.status_code == 201, activity_upload.text
    assert client.delete(f"/api/v1/attachments/{activity_upload.json()['id']}", headers=b).status_code == 404
    assert client.delete(f"/api/v1/attachments/{activity_upload.json()['id']}", headers=a).status_code == 204
    assert client.get('/api/v1/attachments', headers=a, params={'parentType': 'activity', 'parentId': activity['id']}).json() == []

    assert client.delete(f"/api/v1/attachments/{attachment['id']}", headers=a).status_code == 204
    assert client.get(f"/api/v1/attachments/{attachment['id']}/content", headers=a).status_code == 404
    assert client.get('/api/v1/plots/' + plot['id'], headers=a).json()['imageUrl'] is None


def test_attachment_idempotency_is_owner_scoped_and_does_not_duplicate(client, tmp_path, monkeypatch):
    from app.database import settings
    from sqlalchemy import func, select
    from app.database import SessionLocal
    from app.models import Attachment

    monkeypatch.setattr(settings, 'attachment_storage_path', str(tmp_path))
    a = register(client, 'phase5-idempotency-a@example.com')
    b = register(client, 'phase5-idempotency-b@example.com')
    a_plot, _ = make_activity_parent(client, a)
    b_plot, _ = make_activity_parent(client, b)
    key = 'phase5-attachment-retry-1'

    first = upload(client, {**a, 'Idempotency-Key': key}, 'plot', a_plot['id'])
    assert first.status_code == 201, first.text
    attachment = first.json()

    retry = upload(client, {**a, 'Idempotency-Key': key}, 'plot', a_plot['id'])
    assert retry.status_code == 201, retry.text
    assert retry.json() == attachment

    with SessionLocal() as db:
        assert db.scalar(select(func.count()).select_from(Attachment)) == 1

    assert upload(client, {**b, 'Idempotency-Key': key}, 'plot', a_plot['id']).status_code == 404
    other_owner = upload(client, {**b, 'Idempotency-Key': key}, 'plot', b_plot['id'])
    assert other_owner.status_code == 201, other_owner.text
    assert other_owner.json()['id'] != attachment['id']


def test_attachments_reject_invalid_signature_extension_and_oversize(client, tmp_path, monkeypatch):
    from app.database import settings
    monkeypatch.setattr(settings, 'attachment_storage_path', str(tmp_path))
    headers = register(client, 'phase5-validation@example.com')
    plot, _ = make_activity_parent(client, headers)
    assert upload(client, headers, 'plot', plot['id'], PNG, 'fake.jpg').status_code == 415
    assert upload(client, headers, 'plot', plot['id'], JPEG, 'field.gif').status_code == 415
    too_large = b'\xff\xd8\xff' + b'x' * (10 * 1024 * 1024)
    assert upload(client, headers, 'plot', plot['id'], too_large, 'large.jpg').status_code == 413
    assert client.get('/api/v1/attachments', headers=headers, params={'parentType': 'plot', 'parentId': plot['id']}).json() == []


def test_attachments_reject_foreign_and_missing_parents(client, tmp_path, monkeypatch):
    from app.database import settings
    monkeypatch.setattr(settings, 'attachment_storage_path', str(tmp_path))
    a = register(client, 'phase5-parent-a@example.com')
    b = register(client, 'phase5-parent-b@example.com')
    plot, _ = make_activity_parent(client, a)
    assert upload(client, b, 'plot', plot['id']).status_code == 404
    assert upload(client, a, 'plot', str(uuid.uuid4())).status_code == 404
    assert upload(client, a, 'garden', plot['id']).status_code == 422

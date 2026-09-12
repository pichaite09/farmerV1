import uuid
import pytest
from sqlalchemy import text
from app.database import engine


def _register(client, email=None):
    email = email or f'{uuid.uuid4()}@example.com'
    response = client.post('/api/v1/auth/register', json={
        'email': email, 'password': 'Testing-strong-password-42'
    })
    assert response.status_code == 201, response.text
    return response.json()


def _make_admin(token_data):
    with engine.begin() as conn:
        conn.execute(text("UPDATE users SET role='admin' WHERE id=:id"),
                     {'id': token_data['user']['id']})


def test_admin_can_login_and_read_aggregate_dashboard(client):
    farmer = _register(client)
    admin = _register(client)
    _make_admin(admin)
    login = client.post('/api/v1/auth/login', json={
        'email': admin['user']['email'], 'password': 'Testing-strong-password-42'
    })
    assert login.status_code == 200, login.text
    assert login.json()['user']['role'] == 'admin'

    response = client.get('/api/v1/admin/dashboard',
                          headers={'Authorization': 'Bearer ' + login.json()['access_token']})
    assert response.status_code == 200, response.text
    assert response.json()['counts']['users'] == 2
    assert set(response.json()['counts']) == {
        'users', 'plots', 'cycles', 'activities', 'tasks', 'notifications'
    }
    assert client.get('/api/v1/plots', headers={
        'Authorization': 'Bearer ' + login.json()['access_token']
    }).status_code == 403


def test_farmer_cannot_read_admin_dashboard(client):
    farmer = _register(client)
    response = client.get('/api/v1/admin/dashboard', headers={
        'Authorization': 'Bearer ' + farmer['access_token']
    })
    assert response.status_code == 403


def test_public_registration_cannot_self_create_admin(client):
    data = _register(client)
    assert data['user']['role'] == 'farmer'
    response = client.post('/api/v1/auth/register', json={
        'email': f'{uuid.uuid4()}@example.com',
        'password': 'Testing-strong-password-42',
        'role': 'admin',
    })
    assert response.status_code == 422


def test_admin_dashboard_date_filter_and_validation(client):
    admin = _register(client)
    _make_admin(admin)
    token = client.post('/api/v1/auth/login', json={
        'email': admin['user']['email'], 'password': 'Testing-strong-password-42'
    }).json()['access_token']
    headers = {'Authorization': 'Bearer ' + token}
    assert client.get('/api/v1/admin/dashboard?from=2099-01-01', headers=headers).json()['counts']['users'] == 0
    assert client.get('/api/v1/admin/dashboard?from=2025-01-02&to=2025-01-01', headers=headers).status_code == 422


def _admin_headers(client, admin):
    _make_admin(admin)
    login = client.post('/api/v1/auth/login', json={
        'email': admin['user']['email'], 'password': 'Testing-strong-password-42'
    })
    return {'Authorization': 'Bearer ' + login.json()['access_token']}


def _seed_records(owner_id):
    from datetime import date
    from app.database import SessionLocal
    from app.models import Activity, FieldInspection, Plot, ProductionCycle, Task, Transaction, Vehicle, FuelRecord
    with SessionLocal() as db:
        plot = Plot(owner_id=owner_id, name='North field', area=2)
        db.add(plot); db.flush()
        cycle = ProductionCycle(owner_id=owner_id, plot_id=plot.id, name='Rice 2026', crop_type='rice', variety='A', planting_method='direct', start_date=date(2026, 1, 1))
        vehicle = Vehicle(owner_id=owner_id, name='Tractor', category='tractor')
        db.add_all([cycle, vehicle]); db.flush()
        activity = Activity(owner_id=owner_id, cycle_id=cycle.id, type='planting', description='seeded', date=date(2026, 1, 5))
        inspection = FieldInspection(owner_id=owner_id, plot_id=plot.id, cycle_id=cycle.id, inspection_date=date(2026, 1, 6), overall_status='good', checklist={})
        task = Task(owner_id=owner_id, cycle_id=cycle.id, name='Water', due_date=date(2026, 1, 7), status='pending')
        transaction = Transaction(owner_id=owner_id, cycle_id=cycle.id, type='expense', category='fuel', item='diesel', amount=10, date=date(2026, 1, 8))
        db.add_all([activity, inspection, task, transaction]); db.flush()
        fuel = FuelRecord(owner_id=owner_id, vehicle_id=vehicle.id, date=date(2026, 1, 9), fuel_type='diesel', amount=10, transaction_id=transaction.id)
        db.add(fuel); db.commit()
        return {k: str(v.id) for k, v in {'plot': plot, 'cycle': cycle, 'activity': activity, 'inspection': inspection, 'task': task, 'transaction': transaction, 'fuel_record': fuel}.items()}


def test_admin_records_list_is_cross_owner_typed_and_paginated(client):
    farmer_a = _register(client); farmer_b = _register(client); admin = _register(client)
    records_a = _seed_records(farmer_a['user']['id'])
    _seed_records(farmer_b['user']['id'])
    headers = _admin_headers(client, admin)
    response = client.get('/api/v1/admin/records?type=activity&limit=100&offset=0', headers=headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body['type'] == 'activity' and body['limit'] == 100 and body['offset'] == 0
    assert body['total'] == 2 and len(body['items']) == 2
    assert {item['recorder']['id'] for item in body['items']} == {farmer_a['user']['id'], farmer_b['user']['id']}
    page = client.get('/api/v1/admin/records?type=activity&limit=1&offset=1', headers=headers).json()
    assert len(page['items']) == 1
    assert 'passwordHash' not in str(body) and 'p256dh' not in str(body)


@pytest.mark.parametrize('record_type', ['activity', 'task', 'transaction', 'fuel_record'])
def test_admin_records_cycle_linked_context_in_list_and_detail(client, record_type):
    farmer = _register(client); admin = _register(client)
    records = _seed_records(farmer['user']['id'])
    headers = _admin_headers(client, admin)

    listed = client.get('/api/v1/admin/records?type=' + record_type, headers=headers)
    assert listed.status_code == 200, listed.text
    item = listed.json()['items'][0]
    assert item['plot']['id'] == records['plot']
    assert item['cycle']['id'] == records['cycle']

    detail = client.get('/api/v1/admin/records/' + record_type + '/' + records[record_type], headers=headers)
    assert detail.status_code == 200, detail.text
    data = detail.json()
    assert data['recorder']['id'] == farmer['user']['id']
    assert data['plot']['id'] == records['plot'] and data['cycle']['id'] == records['cycle']


def test_admin_records_filters_and_context_detail(client):
    farmer = _register(client); admin = _register(client)
    records = _seed_records(farmer['user']['id'])
    headers = _admin_headers(client, admin)
    response = client.get('/api/v1/admin/records?type=task&from=2026-01-07&to=2026-01-07&owner=' + farmer['user']['id'], headers=headers)
    assert response.status_code == 200 and response.json()['total'] == 1
    filtered = client.get('/api/v1/admin/records?type=activity&plot=' + records['plot'] + '&cycle=' + records['cycle'], headers=headers)
    assert filtered.status_code == 200 and filtered.json()['total'] == 1


def test_admin_records_requires_admin_and_enforces_detail_type_boundary(client):
    farmer = _register(client); admin = _register(client)
    records = _seed_records(farmer['user']['id'])
    assert client.get('/api/v1/admin/records?type=plot', headers={'Authorization': 'Bearer ' + farmer['access_token']}).status_code == 403
    headers = _admin_headers(client, admin)
    assert client.get('/api/v1/admin/records/not-a-type/' + records['plot'], headers=headers).status_code == 422
    assert client.get('/api/v1/admin/records/plot/' + records['activity'], headers=headers).status_code == 404


@pytest.mark.parametrize('record_type, filter_name', [
    ('activity', 'plot'), ('activity', 'cycle'),
    ('field_inspection', 'plot'), ('field_inspection', 'cycle'),
    ('task', 'plot'), ('task', 'cycle'),
    ('production_cycle', 'plot'), ('production_cycle', 'cycle'),
    ('plot', 'plot'),
    ('transaction', 'plot'), ('transaction', 'cycle'),
    ('fuel_record', 'plot'), ('fuel_record', 'cycle'),
])
def test_admin_records_context_filters_match_and_return_zero(client, record_type, filter_name):
    farmer = _register(client); admin = _register(client)
    records = _seed_records(farmer['user']['id'])
    headers = _admin_headers(client, admin)

    matching = client.get(
        f'/api/v1/admin/records?type={record_type}&{filter_name}={records[filter_name]}',
        headers=headers,
    )
    assert matching.status_code == 200, matching.text
    assert matching.json()['total'] == 1

    no_match = client.get(
        f'/api/v1/admin/records?type={record_type}&{filter_name}={uuid.uuid4()}',
        headers=headers,
    )
    assert no_match.status_code == 200, no_match.text
    assert no_match.json()['total'] == 0
    assert no_match.json()['items'] == []


@pytest.mark.parametrize('record_type', [
    'activity', 'field_inspection', 'task', 'production_cycle',
    'transaction', 'fuel_record',
])
def test_admin_records_combined_context_filters_match(client, record_type):
    farmer = _register(client); admin = _register(client)
    records = _seed_records(farmer['user']['id'])
    headers = _admin_headers(client, admin)

    response = client.get(
        f"/api/v1/admin/records?type={record_type}&plot={records['plot']}&cycle={records['cycle']}",
        headers=headers,
    )
    assert response.status_code == 200, response.text
    assert response.json()['total'] == 1




def test_admin_records_rejects_unsupported_context_filter_combination(client):
    farmer = _register(client); admin = _register(client)
    records = _seed_records(farmer['user']['id'])
    headers = _admin_headers(client, admin)

    response = client.get(
        f"/api/v1/admin/records?type=plot&cycle={records['cycle']}",
        headers=headers,
    )
    assert response.status_code == 422


def test_all_records_global_pagination_filters_and_details(client):
    from datetime import datetime, timezone
    from app.database import SessionLocal
    from app.admin import MODELS
    a, b, admin = _register(client), _register(client), _register(client)
    _seed_records(a['user']['id'])
    records_b = _seed_records(b['user']['id'])
    # Interleave types/owners, including equal timestamps: never concatenate pages.
    expected = []
    with SessionLocal() as db:
        for i, (kind, model) in enumerate(MODELS.items()):
            for row in db.query(model).all():
                row.created_at = datetime(2026, 2, 1 + i % 3, tzinfo=timezone.utc)
                expected.append((row.created_at.isoformat(), kind, str(row.id)))
        db.commit()
    headers = _admin_headers(client, admin)
    expected.sort(reverse=True)
    collected = []
    for offset in range(0, 14, 3):
        response = client.get(f'/api/v1/admin/records?type=all&limit=3&offset={offset}', headers=headers)
        assert response.status_code == 200, response.text
        assert response.json()['total'] == 14
        collected.extend((r['type'], r['id']) for r in response.json()['items'])
    assert collected == [(kind, id) for _, kind, id in expected]
    assert client.get('/api/v1/admin/records', headers=headers).json()['total'] == 14
    owned = client.get('/api/v1/admin/records?type=all&owner=' + b['user']['id'], headers=headers).json()
    assert owned['total'] == 7
    assert {r['recorder']['id'] for r in owned['items']} == {b['user']['id']}
    for r in owned['items']:
        detail = client.get(f"/api/v1/admin/records/{r['type']}/{r['id']}", headers=headers)
        assert detail.status_code == 200
        assert detail.json() == r
        assert not any(secret in str(r) for secret in ['password', 'token', 'p256dh'])
    filtered = client.get('/api/v1/admin/records', params={'type': 'all', 'owner': b['user']['id'], 'plot': records_b['plot'], 'cycle': records_b['cycle']}, headers=headers)
    assert filtered.json()['total'] == 6  # plots have no cycle: excluded in all mode
    dated = client.get('/api/v1/admin/records?type=all&from=2026-01-07&to=2026-01-07', headers=headers)
    assert {r['type'] for r in dated.json()['items']} == {'task'}
    assert client.get('/api/v1/admin/records?type=all&offset=99', headers=headers).json()['items'] == []
    assert client.get('/api/v1/admin/records?type=all', headers={'Authorization': 'Bearer ' + a['access_token']}).status_code == 403
    assert client.get('/api/v1/admin/records?type=all').status_code == 401
    assert client.get('/api/v1/admin/records/all/' + records_b['plot'], headers=headers).status_code == 422




def test_admin_attachment_content_is_admin_only_and_owner_safe(client, tmp_path, monkeypatch):
    from app.database import SessionLocal
    from app.models import Attachment, Plot
    from app.database import settings

    monkeypatch.setattr(settings, 'attachment_storage_path', str(tmp_path))
    farmer = _register(client)
    other_farmer = _register(client)
    admin = _register(client)
    with SessionLocal() as db:
        plot = Plot(owner_id=farmer['user']['id'], name='Image plot', area=1)
        db.add(plot)
        db.flush()
        attachment = Attachment(
            owner_id=farmer['user']['id'], parent_type='plot', parent_id=plot.id,
            storage_name='safe.png', content_type='image/png', size_bytes=4,
        )
        db.add(attachment)
        db.commit()
        attachment_id = str(attachment.id)
    (tmp_path / 'safe.png').write_bytes(b'PNG!')
    farmer_headers = {'Authorization': 'Bearer ' + farmer['access_token']}
    other_headers = {'Authorization': 'Bearer ' + other_farmer['access_token']}
    admin_headers = _admin_headers(client, admin)
    path = f'/api/v1/admin/attachments/{attachment_id}/content'
    assert client.get(path).status_code == 401
    assert client.get(path, headers=farmer_headers).status_code == 403
    assert client.get(path, headers=other_headers).status_code == 403
    response = client.get(path, headers=admin_headers)
    assert response.status_code == 200
    assert response.headers['content-type'] == 'image/png'
    assert response.content == b'PNG!'
    assert client.get(f'/api/v1/attachments/{attachment_id}/content', headers=other_headers).status_code == 404
    assert client.get(f'/api/v1/attachments/{attachment_id}/content', headers=farmer_headers).status_code == 200


def test_admin_plot_created_on_to_date_is_included(client):
    from datetime import datetime, timezone
    from app.database import SessionLocal
    from app.models import Plot

    farmer = _register(client); admin = _register(client)
    with SessionLocal() as db:
        plot = Plot(owner_id=farmer['user']['id'], name='Late plot', area=1)
        db.add(plot); db.flush()
        plot.created_at = datetime(2026, 1, 7, 23, 59, tzinfo=timezone.utc)
        db.commit()
        plot_id = str(plot.id)
    headers = _admin_headers(client, admin)

    response = client.get('/api/v1/admin/records?type=plot&from=2026-01-07&to=2026-01-07', headers=headers)
    assert response.status_code == 200, response.text
    assert response.json()['total'] == 1
    assert response.json()['items'][0]['id'] == plot_id

import io

PASSWORD = 'Field-inspection-strong-password-42'
JPEG = b'\xff\xd8\xff\xe0inspection'


def register(client, email):
    response = client.post('/api/v1/auth/register', json={'email': email, 'password': PASSWORD})
    assert response.status_code == 201, response.text
    return {'Authorization': 'Bearer ' + response.json()['access_token']}


def plot(client, headers, name='North'):
    response = client.post('/api/v1/plots', headers=headers, json={'name': name, 'area': 2, 'soil': 'loam'})
    assert response.status_code == 201, response.text
    return response.json()


def inspection_body(plot_id, cycle_id=None):
    return {
        'plotId': plot_id,
        'cycleId': cycle_id,
        'inspectionDate': '2026-09-10',
        'overallStatus': 'good',
        'checklist': {'irrigation': True, 'pests': False},
        'notes': 'Looks healthy',
        'recommendation': 'Continue monitoring',
        'followUpRequired': False,
    }


def upload(client, headers, inspection_id, parent_type='field_inspection'):
    return client.post(
        '/api/v1/attachments',
        headers=headers,
        data={'parentType': parent_type, 'parentId': inspection_id},
        files={'file': ('inspection.jpg', io.BytesIO(JPEG), 'image/jpeg')},
    )


def test_field_inspections_are_owner_scoped_and_full_crud(client):
    owner = register(client, 'inspection-owner@example.com')
    other = register(client, 'inspection-other@example.com')
    p = plot(client, owner)
    created = client.post('/api/v1/field-inspections', headers=owner, json=inspection_body(p['id']))
    assert created.status_code == 201, created.text
    item = created.json()
    assert item['plotId'] == p['id']
    assert client.get('/api/v1/field-inspections', headers=other).json() == []
    assert client.get(f"/api/v1/field-inspections/{item['id']}", headers=other).status_code == 404
    assert client.patch(f"/api/v1/field-inspections/{item['id']}", headers=owner, json={'notes': 'Updated'}).json()['notes'] == 'Updated'
    assert client.delete(f"/api/v1/field-inspections/{item['id']}", headers=owner).status_code == 204


def test_field_inspection_validates_cycle_plot_and_allows_multiple_attachments(client, tmp_path, monkeypatch):
    from app.database import settings
    monkeypatch.setattr(settings, 'attachment_storage_path', str(tmp_path))
    owner = register(client, 'inspection-validation@example.com')
    p1 = plot(client, owner, 'One')
    p2 = plot(client, owner, 'Two')
    cycle = client.post('/api/v1/cycles', headers=owner, json={
        'name': 'Rice', 'plotId': p1['id'], 'cropType': 'rice', 'variety': 'local',
        'plantingMethod': 'direct', 'startDate': '2026-09-01',
    }).json()
    assert client.post('/api/v1/field-inspections', headers=owner, json=inspection_body(p2['id'], cycle['id'])).status_code == 422
    assert client.post('/api/v1/field-inspections', headers=owner, json={**inspection_body(p1['id']), 'overallStatus': ' '}).status_code == 422
    item = client.post('/api/v1/field-inspections', headers=owner, json=inspection_body(p1['id'], cycle['id'])).json()
    assert upload(client, owner, item['id']).status_code == 201
    assert upload(client, owner, item['id']).status_code == 201
    attachments = client.get('/api/v1/attachments', headers=owner, params={'parentType': 'field_inspection', 'parentId': item['id']})
    assert attachments.status_code == 200
    assert len(attachments.json()) == 2


def test_follow_up_inspection_creates_one_linked_task_and_retries_are_idempotent(client):
    owner = register(client, 'inspection-follow-up@example.com')
    p = plot(client, owner)
    cycle = client.post('/api/v1/cycles', headers=owner, json={
        'name': 'Rice', 'plotId': p['id'], 'cropType': 'rice', 'variety': 'local',
        'plantingMethod': 'direct', 'startDate': '2026-09-01',
    }).json()
    body = {**inspection_body(p['id'], cycle['id']), 'followUpRequired': True, 'followUpDate': '2026-09-20'}
    created = client.post('/api/v1/field-inspections', headers=owner, json=body)
    assert created.status_code == 201, created.text
    inspection = created.json()
    tasks = client.get('/api/v1/tasks', headers=owner).json()
    assert len(tasks) == 1
    assert tasks[0]['id'] == inspection['followUpTaskId']
    assert tasks[0]['name'] == 'Looks healthy'
    assert tasks[0]['cycleId'] == cycle['id']
    assert tasks[0]['dueDate'] == '2026-09-20'
    assert tasks[0]['fieldInspectionId'] == inspection['id']
    assert tasks[0]['isAutomaticFollowUp'] is True
    task_upload = upload(client, owner, inspection['followUpTaskId'], 'task')
    assert task_upload.status_code == 201, task_upload.text
    task_attachments = client.get('/api/v1/attachments', headers=owner, params={
        'parentType': 'task', 'parentId': inspection['followUpTaskId'],
    })
    assert task_attachments.status_code == 200
    assert len(task_attachments.json()) == 1

    patched = client.patch('/api/v1/field-inspections/' + inspection['id'], headers=owner, json={
        'followUpRequired': True, 'followUpDate': '2026-09-20', 'cycleId': cycle['id'],
    })
    assert patched.status_code == 200, patched.text
    assert len(client.get('/api/v1/tasks', headers=owner).json()) == 1
    assert patched.json()['followUpTaskId'] == inspection['followUpTaskId']


def test_follow_up_date_updates_same_task_and_task_completion_is_reflected(client):
    owner = register(client, 'inspection-follow-up-update@example.com')
    p = plot(client, owner)
    cycle = client.post('/api/v1/cycles', headers=owner, json={
        'name': 'Rice', 'plotId': p['id'], 'cropType': 'rice', 'variety': 'local',
        'plantingMethod': 'direct', 'startDate': '2026-09-01',
    }).json()
    inspection = client.post('/api/v1/field-inspections', headers=owner, json={
        **inspection_body(p['id'], cycle['id']), 'followUpRequired': True, 'followUpDate': '2026-09-20',
    }).json()
    changed = client.patch('/api/v1/field-inspections/' + inspection['id'], headers=owner, json={
        'followUpDate': '2026-09-25',
        'notes': 'ตรวจซ้ำบริเวณแถวริมแปลง',
    })
    assert changed.status_code == 200, changed.text
    assert changed.json()['followUpTaskId'] == inspection['followUpTaskId']
    task = client.get('/api/v1/tasks', headers=owner).json()[0]
    assert task['dueDate'] == '2026-09-25'
    assert task['name'] == 'ตรวจซ้ำบริเวณแถวริมแปลง'

    completed = client.patch('/api/v1/tasks/' + task['id'], headers=owner, json={'status': 'completed'})
    assert completed.status_code == 200, completed.text
    refreshed = client.get('/api/v1/field-inspections/' + inspection['id'], headers=owner)
    assert refreshed.json()['followUpStatus'] == 'completed'


def test_follow_up_without_cycle_saves_but_creates_no_task_and_is_owner_scoped(client):
    owner = register(client, 'inspection-follow-up-no-cycle@example.com')
    other = register(client, 'inspection-follow-up-other@example.com')
    p = plot(client, owner)
    created = client.post('/api/v1/field-inspections', headers=owner, json={
        **inspection_body(p['id']), 'followUpRequired': True, 'followUpDate': '2026-09-20',
    })
    assert created.status_code == 201, created.text
    assert created.json()['followUpTaskId'] is None
    assert created.json()['followUpStatus'] is None
    assert client.get('/api/v1/tasks', headers=owner).json() == []
    assert client.get('/api/v1/field-inspections/' + created.json()['id'], headers=other).status_code == 404

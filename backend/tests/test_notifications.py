from datetime import date, timedelta

from test_phase2_resources import register, plot, cycle_body


def make_task(client, headers, cycle_id, due_date, name='Irrigate'):
    response = client.post(
        '/api/v1/tasks',
        headers=headers,
        json={
            'name': name,
            'cycleId': cycle_id,
            'dueDate': due_date.isoformat(),
            'status': 'pending',
            'description': 'Reminder test',
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_notifications_can_mark_read_and_clear_only_read_items(client):
    tomorrow = date.today() + timedelta(days=1)
    owner = register(client, 'notifications-read@example.com')
    cycle = client.post(
        '/api/v1/cycles', headers=owner, json=cycle_body(plot(client, owner)['id'])
    ).json()
    first = make_task(client, owner, cycle['id'], tomorrow, 'Read task')
    second = make_task(client, owner, cycle['id'], tomorrow, 'Unread task')
    listed = client.get('/api/v1/notifications', headers=owner).json()
    read_item = next(x for x in listed if x['taskId'] == first['id'])
    response = client.patch(
        f"/api/v1/notifications/{read_item['id']}/read", headers=owner
    )
    assert response.status_code == 200
    assert response.json()['readAt'] is not None
    assert client.delete('/api/v1/notifications/read', headers=owner).status_code == 204
    remaining = client.get('/api/v1/notifications', headers=owner).json()
    assert [x['taskId'] for x in remaining] == [second['id']]


    response = client.get('/api/v1/notifications')
    assert response.status_code == 401


def test_notifications_are_owner_scoped_and_idempotent(client):
    today = date.today()
    tomorrow = today + timedelta(days=1)
    owner_a = register(client, 'notifications-a@example.com')
    owner_b = register(client, 'notifications-b@example.com')
    cycle_a = client.post(
        '/api/v1/cycles',
        headers=owner_a,
        json=cycle_body(plot(client, owner_a)['id']),
    ).json()
    cycle_b = client.post(
        '/api/v1/cycles',
        headers=owner_b,
        json=cycle_body(plot(client, owner_b)['id']),
    ).json()
    task_a = make_task(client, owner_a, cycle_a['id'], tomorrow, 'A task')
    make_task(client, owner_b, cycle_b['id'], tomorrow, 'B task')
    make_task(client, owner_a, cycle_a['id'], today, 'Today task')
    completed = make_task(client, owner_a, cycle_a['id'], tomorrow, 'Completed task')
    client.patch(
        '/api/v1/tasks/' + completed['id'],
        headers=owner_a,
        json={'status': 'completed'},
    )
    client.patch(
        '/api/v1/tasks/' + task_a['id'],
        headers=owner_a,
        json={'status': 'completed'},
    )
    # Recreate one eligible task after proving completed tasks are excluded.
    eligible = make_task(client, owner_a, cycle_a['id'], tomorrow, 'Eligible task')

    first = client.get('/api/v1/notifications', headers=owner_a)
    assert first.status_code == 200, first.text
    assert [item['taskId'] for item in first.json()] == [eligible['id']]
    assert first.json()[0]['dueDate'] == tomorrow.isoformat()
    assert first.json()[0]['taskName'] == 'Eligible task'
    assert first.json()[0]['cycleName'] == cycle_a['name']
    assert first.json()[0]['plotName']

    second = client.get('/api/v1/notifications', headers=owner_a)
    assert second.status_code == 200, second.text
    assert second.json() == first.json()
    assert client.get('/api/v1/notifications', headers=owner_b).json()[0]['taskId'] != eligible['id']

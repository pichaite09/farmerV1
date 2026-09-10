from decimal import Decimal

PASSWORD = 'Production-summary-strong-password-42'


def register(client, email):
    response = client.post('/api/v1/auth/register', json={'email': email, 'password': PASSWORD})
    assert response.status_code == 201, response.text
    return {'Authorization': 'Bearer ' + response.json()['access_token']}


def plot(client, headers, name):
    response = client.post('/api/v1/plots', headers=headers, json={
        'name': name, 'area': 2, 'soil': 'loam',
    })
    assert response.status_code == 201, response.text
    return response.json()


def cycle(client, headers, plot_id, name, start_date='2026-09-01', status='active'):
    response = client.post('/api/v1/cycles', headers=headers, json={
        'name': name, 'plotId': plot_id, 'cropType': 'rice', 'variety': 'local',
        'plantingMethod': 'direct', 'startDate': start_date, 'status': status,
    })
    assert response.status_code == 201, response.text
    return response.json()


def transaction(client, headers, cycle_id, kind, amount, date='2026-09-10', item='rice'):
    response = client.post('/api/v1/transactions', headers=headers, json={
        'type': kind, 'category': 'sales' if kind == 'income' else 'labor',
        'item': item, 'amount': amount, 'date': date, 'cycleId': cycle_id,
    })
    assert response.status_code == 201, response.text
    return response.json()


def test_summary_is_owner_scoped_and_separates_cycles_with_activity_tasks_and_totals(client):
    owner = register(client, 'summary-owner@example.com')
    other = register(client, 'summary-other@example.com')
    owner_plot = plot(client, owner, 'North')
    other_plot = plot(client, other, 'Other')
    first = cycle(client, owner, owner_plot['id'], 'First')
    second = cycle(client, owner, owner_plot['id'], 'Second', '2026-09-02', 'completed')
    foreign = cycle(client, other, other_plot['id'], 'Foreign')

    client.post('/api/v1/activities', headers=owner, json={
        'cycleId': first['id'], 'type': 'fertilize', 'description': 'Feed', 'date': '2026-09-05',
    })
    task = client.post('/api/v1/tasks', headers=owner, json={
        'name': 'Done task', 'cycleId': first['id'], 'dueDate': '2026-09-06', 'status': 'pending',
    }).json()
    client.post('/api/v1/tasks', headers=owner, json={
        'name': 'Open task', 'cycleId': first['id'], 'dueDate': '2026-09-07', 'status': 'in_progress',
    })
    client.patch('/api/v1/tasks/' + task['id'], headers=owner, json={'status': 'completed'})
    transaction(client, owner, first['id'], 'income', '100.00')
    transaction(client, owner, first['id'], 'expense', '35.50')
    transaction(client, owner, second['id'], 'income', '200.00')
    transaction(client, owner, None, 'income', '999.00', item='unassigned')
    assert client.post('/api/v1/transactions', headers=other, json={
        'type': 'income', 'category': 'sales', 'item': 'foreign', 'amount': '500',
        'date': '2026-09-10', 'cycleId': foreign['id'],
    }).status_code == 201

    response = client.get('/api/v1/reports/production-cycles/summary', headers=owner)
    assert response.status_code == 200, response.text
    summaries = response.json()
    assert {item['cycleId'] for item in summaries} == {first['id'], second['id']}
    by_id = {item['cycleId']: item for item in summaries}
    assert by_id[first['id']]['plotName'] == 'North'
    assert by_id[first['id']]['cycleName'] == 'First'
    assert by_id[first['id']]['status'] == 'active'
    assert by_id[first['id']]['activities'][0]['type'] == 'fertilize'
    assert by_id[first['id']]['taskCount'] == 2
    assert by_id[first['id']]['completedTaskCount'] == 1
    assert by_id[first['id']]['income'] == 100
    assert by_id[first['id']]['expense'] == Decimal('35.50')
    assert by_id[first['id']]['profit'] == Decimal('64.50')
    assert by_id[second['id']]['status'] == 'completed'
    assert by_id[second['id']]['income'] == 200
    assert by_id[second['id']]['expense'] == 0
    assert by_id[second['id']]['profit'] == 200
    other_summaries = client.get('/api/v1/reports/production-cycles/summary', headers=other).json()
    assert len(other_summaries) == 1
    assert other_summaries[0]['cycleId'] == foreign['id']
    assert other_summaries[0]['income'] == 500


def test_summary_includes_empty_cycles_and_validates_date_range(client):
    owner = register(client, 'summary-empty@example.com')
    p = plot(client, owner, 'Empty')
    cycle(client, owner, p['id'], 'No records')
    response = client.get('/api/v1/reports/production-cycles/summary', headers=owner)
    assert response.status_code == 200
    item = response.json()[0]
    assert item['activities'] == []
    assert item['taskCount'] == 0
    assert item['completedTaskCount'] == 0
    assert item['income'] == 0
    assert item['expense'] == 0
    assert item['profit'] == 0
    invalid = client.get('/api/v1/reports/production-cycles/summary', headers=owner,
                         params={'from': '2026-09-20', 'to': '2026-09-01'})
    assert invalid.status_code == 422

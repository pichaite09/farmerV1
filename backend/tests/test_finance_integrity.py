from decimal import Decimal

PASSWORD = 'Finance-integrity-strong-password-42'


def register(client, email):
    response = client.post(
        '/api/v1/auth/register',
        json={'email': email, 'password': PASSWORD},
    )
    assert response.status_code == 201, response.text
    return {'Authorization': 'Bearer ' + response.json()['access_token']}


def test_dashboard_counts_unlinked_fuel_once_and_beyond_recent_limit(client):
    headers = register(client, 'finance-integrity@example.com')
    vehicle = client.post(
        '/api/v1/vehicles',
        headers=headers,
        json={'name': 'Tractor', 'category': 'tractor'},
    ).json()

    for index in range(11):
        response = client.post(
            '/api/v1/fuel-records',
            headers=headers,
            json={
                'vehicleId': vehicle['id'],
                'date': '2026-09-10',
                'fuelType': 'diesel',
                'amount': '2.00',
                'details': f'unlinked-{index}',
            },
        )
        assert response.status_code == 201, response.text

    linked = client.post(
        '/api/v1/transactions',
        headers=headers,
        json={
            'type': 'expense',
            'category': 'น้ำมันเชื้อเพลิง',
            'item': 'linked fuel',
            'amount': '7.00',
            'date': '2026-09-10',
            'fuel': {'vehicleId': vehicle['id'], 'fuelType': 'diesel'},
        },
    )
    assert linked.status_code == 201, linked.text

    dashboard = client.get(
        '/api/v1/dashboard?from=2026-09-01&to=2026-09-30',
        headers=headers,
    )
    assert dashboard.status_code == 200, dashboard.text
    payload = dashboard.json()
    assert Decimal(str(payload['fuelSpend'])) == Decimal('22.00')
    assert Decimal(str(payload['expense'])) == Decimal('29.00')
    assert len(payload['recentFuelRecords']) == 10


def test_transaction_fuel_link_stays_in_sync_when_transaction_changes(client):
    headers = register(client, 'finance-sync@example.com')
    vehicle = client.post(
        '/api/v1/vehicles',
        headers=headers,
        json={'name': 'Tractor', 'category': 'tractor'},
    ).json()
    created = client.post(
        '/api/v1/transactions',
        headers=headers,
        json={
            'type': 'expense',
            'category': 'น้ำมันเชื้อเพลิง',
            'item': 'linked fuel',
            'amount': '7.00',
            'date': '2026-09-10',
            'fuel': {'vehicleId': vehicle['id'], 'fuelType': 'diesel'},
        },
    )
    assert created.status_code == 201, created.text

    updated = client.patch(
        '/api/v1/transactions/' + created.json()['id'],
        headers=headers,
        json={'amount': '9.50', 'date': '2026-09-11'},
    )
    assert updated.status_code == 200, updated.text

    fuel = client.get('/api/v1/fuel-records', headers=headers).json()
    assert len(fuel) == 1
    assert fuel[0]['amount'] == '9.50'
    assert fuel[0]['date'] == '2026-09-11'


def test_cycle_write_rejects_completed_destination(client):
    headers = register(client, 'finance-cycle-integrity@example.com')
    plot = client.post(
        '/api/v1/plots',
        headers=headers,
        json={'name': 'North', 'area': '2.00'},
    ).json()
    cycle = client.post(
        '/api/v1/cycles',
        headers=headers,
        json={
            'name': 'Rice',
            'plotId': plot['id'],
            'cropType': 'rice',
            'variety': 'local',
            'plantingMethod': 'direct',
            'startDate': '2026-09-01',
        },
    ).json()
    completed = client.patch(
        '/api/v1/cycles/' + cycle['id'],
        headers=headers,
        json={'status': 'completed'},
    )
    assert completed.status_code == 200, completed.text
    activity = client.post(
        '/api/v1/activities',
        headers=headers,
        json={
            'cycleId': cycle['id'],
            'type': 'fertilize',
            'date': '2026-09-10',
            'description': 'should be rejected',
            'completeCycle': True,
        },
    )
    assert activity.status_code == 409, activity.text

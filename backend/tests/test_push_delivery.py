from datetime import date, timedelta

from sqlalchemy import select

from app.database import SessionLocal
from app.models import PushOutbox
from app.push import claim_push_outbox, deliver_claimed, enqueue_push_outbox
from app.notifications import generate_daily_reminders
from test_phase2_resources import register, plot, cycle_body

SUB = lambda endpoint: {'endpoint': endpoint, 'keys': {'p256dh': 'A' * 87, 'auth': 'B' * 22}}


def _task(client, owner, cycle_id, name='Task'):
    result = client.post('/api/v1/tasks', headers=owner, json={
        'name': name, 'cycleId': cycle_id,
        'dueDate': (date.today() + timedelta(days=1)).isoformat(), 'status': 'pending',
    })
    assert result.status_code == 201, result.text
    return result.json()


def test_outbox_generation_is_idempotent_and_owner_scoped(client):
    owner = register(client, 'outbox-owner@example.com')
    other = register(client, 'outbox-other@example.com')
    cycle = client.post('/api/v1/cycles', headers=owner, json=cycle_body(plot(client, owner)['id'])).json()
    other_cycle = client.post('/api/v1/cycles', headers=other, json=cycle_body(plot(client, other)['id'])).json()
    task = _task(client, owner, cycle['id'])
    _task(client, other, other_cycle['id'], 'Other')
    assert client.post('/api/v1/push/subscriptions', headers=owner, json=SUB('https://fcm.googleapis.com/a')).status_code == 201
    with SessionLocal() as db:
        reminders = generate_daily_reminders(db, today=date.today(), owner_id=None)
        assert enqueue_push_outbox(db, reminders) == 1
        assert enqueue_push_outbox(db, reminders) == 0
        owner_reminders = [x for x in reminders if str(x.task_id) == task['id']]
        assert len(owner_reminders) == 1
        rows = db.scalars(select(PushOutbox).where(PushOutbox.owner_id == owner_reminders[0].owner_id)).all()
        assert len(rows) == 1
        assert rows[0].notification_id in {x.id for x in reminders if str(x.task_id) == task['id']}
        assert rows[0].payload['notificationId'] == str(rows[0].notification_id)


def test_completed_and_cancelled_tasks_are_suppressed(client):
    owner = register(client, 'outbox-suppression@example.com')
    cycle = client.post('/api/v1/cycles', headers=owner, json=cycle_body(plot(client, owner)['id'])).json()
    completed = _task(client, owner, cycle['id'], 'Completed')
    cancelled = _task(client, owner, cycle['id'], 'Cancelled')
    with SessionLocal() as db:
        initial = generate_daily_reminders(db, today=date.today())
        assert {str(item.task_id) for item in initial} == {completed['id'], cancelled['id']}
        client.patch('/api/v1/tasks/' + completed['id'], headers=owner, json={'status': 'completed'})
        cancelled_response = client.patch('/api/v1/tasks/' + cancelled['id'], headers=owner, json={'status': 'cancelled'})
        assert cancelled_response.status_code == 200, cancelled_response.text
        db.expire_all()
        reminders = generate_daily_reminders(db, today=date.today())
        assert str(completed['id']) not in {str(x.task_id) for x in reminders}
        assert str(cancelled['id']) not in {str(x.task_id) for x in reminders}


def test_invalid_endpoint_is_rejected_before_provider(monkeypatch):
    from app.push import send_web_push
    called = []
    monkeypatch.setattr('app.push.settings.vapid_private_key', 'private')
    monkeypatch.setattr('app.push.settings.vapid_subject', 'mailto:test@example.com')
    monkeypatch.setattr('app.push.pywebpush', lambda **kwargs: called.append(kwargs))
    assert send_web_push(SUB('https://127.0.0.1/private'), {'title': 'x'}) is False
    assert called == []


def test_claim_is_atomic_and_failure_retries_without_blocking_other_subscriptions(client, monkeypatch):
    owner = register(client, 'outbox-delivery@example.com')
    cycle = client.post('/api/v1/cycles', headers=owner, json=cycle_body(plot(client, owner)['id'])).json()
    _task(client, owner, cycle['id'])
    for endpoint in ('https://fcm.googleapis.com/a', 'https://fcm.googleapis.com/b'):
        assert client.post('/api/v1/push/subscriptions', headers=owner, json=SUB(endpoint)).status_code == 201
    with SessionLocal() as db:
        reminders = generate_daily_reminders(db, today=date.today())
        enqueue_push_outbox(db, reminders)
        claimed = claim_push_outbox(db, limit=10)
        assert len(claimed) == 2
        assert claim_push_outbox(db, limit=10) == []
        calls = []
        def provider(subscription, payload):
            calls.append(subscription['endpoint'])
            if subscription['endpoint'].endswith('/a'):
                raise RuntimeError('temporary')
            return True
        monkeypatch.setattr('app.push.send_web_push', provider)
        sent, failed = deliver_claimed(db, claimed)
        assert (sent, failed) == (1, 0)
        states = db.scalars(select(PushOutbox).order_by(PushOutbox.created_at)).all()
        assert {x.status for x in states} == {'pending', 'sent'}
        assert len(calls) == 2

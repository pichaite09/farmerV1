"""Exercise real migration DDL transactionally with synthetic rows only."""
import importlib.util
from pathlib import Path
import uuid

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
import pytest

from app.database import engine
from test_admin_announcements import register, admin_headers


def test_migration_excludes_every_preexisting_draft_and_is_immutable(client):
    farmer, admin = register(client), register(client)
    auth = admin_headers(client, admin)
    response = client.post('/api/v1/admin/announcements', headers=auth, json={
        'title': 'Synthetic future timestamp draft', 'body': 'fixture',
        'targetType': 'selected', 'userIds': [farmer['user']['id']],
    })
    assert response.status_code == 201
    aid = uuid.UUID(response.json()['id'])
    assert engine.url.database == 'farmer_main_test' and engine.url.host == 'postgres'
    path = Path(__file__).parents[1] / 'migrations/versions/0025_announcement_cutoff.py'
    spec = importlib.util.spec_from_file_location('cutoff_migration', path)
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            # DDL and future fixture timestamps roll back together. Never downgrade
            # a real database or replace its durable activation boundary.
            connection.execute(text("UPDATE announcements SET created_at='2099-01-01T00:00:00Z' WHERE id=:id"), {'id': aid})
            connection.execute(text('DROP TABLE announcement_delivery_policy'))
            connection.execute(text('DROP FUNCTION protect_announcement_delivery_policy()'))
            with Operations.context(MigrationContext.configure(connection)):
                migration.upgrade()
            assert connection.scalar(text('SELECT count(*) FROM announcements WHERE created_at >= (SELECT activated_at FROM announcement_delivery_policy)')) == 0
            assert connection.scalar(text("SELECT status FROM announcements WHERE id=:id"), {'id': aid}) == 'draft'
            for sql in ('UPDATE announcement_delivery_policy SET activated_at=now()',
                        'DELETE FROM announcement_delivery_policy',
                        'TRUNCATE announcement_delivery_policy'):
                with connection.begin_nested() as savepoint:
                    with pytest.raises(DBAPIError, match='immutable'):
                        connection.execute(text(sql))
                    savepoint.rollback()
        finally:
            transaction.rollback()

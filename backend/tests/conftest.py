import os

import pytest
from sqlalchemy import text
from sqlalchemy.engine import make_url
from fastapi.testclient import TestClient
from app.main import app
from app.database import engine

def _assert_isolated_database():
    database_url = make_url(str(engine.url))
    assert database_url.database == 'farmer_main_test', 'Tests require isolated farmer_main_test DB'
    assert database_url.host in {'127.0.0.1', 'localhost', 'postgres'}, 'Tests must use a local/isolated database host'
    assert os.getenv('CI') or os.getenv('ALLOW_DESTRUCTIVE_TEST_DB') == '1', (
        'Set ALLOW_DESTRUCTIVE_TEST_DB=1 only for the isolated test database'
    )


@pytest.fixture(autouse=True)
def isolated_database():
    _assert_isolated_database()
    with engine.begin() as conn:
        conn.execute(text('TRUNCATE push_outbox, push_subscriptions, notifications, attachments, field_inspections, fuel_records, transactions, tasks, category_settings, vehicles, activities, production_cycles, plots, sessions, users, auth_throttles'))
    yield
    with engine.begin() as conn:
        conn.execute(text('TRUNCATE push_outbox, push_subscriptions, notifications, attachments, field_inspections, fuel_records, transactions, tasks, category_settings, vehicles, activities, production_cycles, plots, sessions, users, auth_throttles'))

@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c

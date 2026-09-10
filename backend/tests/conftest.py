import pytest
from sqlalchemy import text
from sqlalchemy.engine import make_url
from fastapi.testclient import TestClient
from app.main import app
from app.database import engine

@pytest.fixture(autouse=True)
def isolated_database():
    assert make_url(str(engine.url)).database == 'farmer_main_test', 'Tests require isolated farmer_main_test DB'
    with engine.begin() as conn:
        conn.execute(text('TRUNCATE push_subscriptions, notifications, attachments, field_inspections, fuel_records, transactions, tasks, category_settings, vehicles, activities, production_cycles, plots, sessions, users, auth_throttles'))
    yield
    with engine.begin() as conn:
        conn.execute(text('TRUNCATE push_subscriptions, notifications, attachments, field_inspections, fuel_records, transactions, tasks, category_settings, vehicles, activities, production_cycles, plots, sessions, users, auth_throttles'))

@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c

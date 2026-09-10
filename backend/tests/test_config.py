import importlib
import pytest


def test_secrets_are_required(monkeypatch):
    for key in ('DATABASE_URL', 'JWT_SECRET', 'CORS_ORIGINS'):
        monkeypatch.delenv(key, raising=False)
    assert importlib.util.find_spec('app.config') is not None, 'configuration module missing'
    from app.config import Settings
    with pytest.raises(ValueError):
        Settings(_env_file=None)

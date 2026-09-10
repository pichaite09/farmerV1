# Testing and isolated staging

## Safety rules

- Tests may only use a database named `farmer_main_test`.
- Never point `backend/tests` at Production or at a database containing real farmer data.
- The test fixture truncates tables before and after each test. It is intentionally destructive inside the isolated test database.
- Staging uses separate PostgreSQL and attachment volumes: `farmer_main_staging_postgres_data` and `farmer_main_staging_attachment_data`.
- Keep all staging secrets in an untracked environment file or secret manager. Do not commit values.

## Local backend test

```bash
python3 -m venv .venv-test
. .venv-test/bin/activate
pip install -r backend/requirements-dev.txt
export DATABASE_URL='postgresql+psycopg://farmer_main_test:[REDACTED]@127.0.0.1:5432/farmer_main_test'
export JWT_SECRET='[REDACTED]'
export CORS_ORIGINS='["http://localhost:8091"]'
export ALLOW_DESTRUCTIVE_TEST_DB=1
cd backend
alembic upgrade head
python -m pytest -q
```

Use a disposable PostgreSQL instance. Do not use the Production database or its volume.

## Isolated staging

Create an untracked `deploy/staging/.env` containing `STAGING_POSTGRES_PASSWORD`, `STAGING_JWT_SECRET`, and optional `STAGING_CORS_ORIGINS`, then build the web artifact into `deploy/staging/web/` and run:

```bash
cd deploy/staging
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build
curl -fsS http://127.0.0.1:8091/health/ready
```

Verify that the API connects to `farmer_main_test` and that the volumes are the staging volumes before loading any fixture. Destroy only the isolated stack when finished:

```bash
docker compose --env-file .env down -v
```

## CI gates

GitHub Actions runs isolated PostgreSQL migrations and backend tests, then Flutter dependency resolution, analyze, tests, and Web release build. CI credentials are test-only values supplied by the workflow and must never be reused in Production.

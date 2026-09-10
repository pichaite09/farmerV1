#!/bin/sh
set -eu
NAME=farmer-followup-test-db
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
docker run -d --name "$NAME" --network container:farmer-main-api-1 -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=farmer_main_test postgres:16-alpine >/dev/null
ready=0
for i in $(seq 1 30); do
  if docker exec "$NAME" pg_isready -h 127.0.0.1 -U test -d farmer_main_test >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ]
docker exec -e DATABASE_URL=postgresql+psycopg://test:test@127.0.0.1:5432/farmer_main_test -e JWT_SECRET=isolated-followup-test-secret-012345678901234567890123456789 -e CORS_ORIGINS='["http://localhost:8091"]' -e ATTACHMENT_STORAGE_PATH=/tmp/farmer-attachments -w /tmp/farmer-main-followup-check/backend farmer-main-api-1 sh -lc 'alembic upgrade head >/dev/null && PYTHONPATH=. pytest -q tests'

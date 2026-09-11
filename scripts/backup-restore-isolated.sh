#!/usr/bin/env bash
# Exercise pg_dump/restore only inside a disposable, localhost-isolated container.
set -Eeuo pipefail

command -v docker >/dev/null 2>&1 || { echo "BLOCKED: docker is required" >&2; exit 2; }
docker compose version >/dev/null 2>&1 || { echo "BLOCKED: docker compose is required" >&2; exit 2; }

name="farmer-phase5-pg-$RANDOM-$$"
password='phase5-isolated-only'
dump=$(mktemp)
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; rm -f "$dump"; }
trap cleanup EXIT

docker run --detach --name "$name" -e POSTGRES_USER=phase5 -e POSTGRES_PASSWORD="$password" \
  -e POSTGRES_DB=phase5 --network none postgres:16-alpine >/dev/null
for _ in $(seq 1 30); do
  docker exec "$name" pg_isready -U phase5 -d phase5 >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$name" pg_isready -U phase5 -d phase5 >/dev/null

docker exec -i "$name" psql -U phase5 -d phase5 <<'SQL'
CREATE TABLE recovery_probe (id integer PRIMARY KEY, marker text NOT NULL);
INSERT INTO recovery_probe VALUES (1, 'backup-restore-ok');
SQL
docker exec "$name" pg_dump -U phase5 -d phase5 --format=custom > "$dump"
docker exec -i "$name" psql -U phase5 -d phase5 -c 'DROP TABLE recovery_probe;' >/dev/null
docker exec -i "$name" pg_restore -U phase5 -d phase5 --exit-on-error < "$dump"
marker=$(docker exec "$name" psql -U phase5 -d phase5 -Atc 'SELECT marker FROM recovery_probe WHERE id=1;')
test "$marker" = backup-restore-ok
echo "PASS: isolated PostgreSQL custom-format backup/restore round trip"

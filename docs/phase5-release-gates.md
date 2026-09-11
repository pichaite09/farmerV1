# Phase 5 reproducible release and recovery gates

These checks are safe to run before an explicit deployment command. They do not
start the production Compose project, publish an image, build an Android APK/AAB,
or read signing credentials.

## Local gates

From the repository root:

```sh
bash scripts/phase5-gates.sh compose
bash scripts/backup-restore-isolated.sh
```

`phase5-gates.sh compose` validates the staging Compose model with disposable
values, checks the same-origin nginx proxy and the 10 MiB application upload
contract, rejects tracked signing material, and confirms the Web build keeps
`FARM_API_BASE_URL=/`. Use `bash scripts/phase5-gates.sh all` to additionally
run a clean Flutter Web release build when Flutter is installed. The generated
`build/` output is ignored and is not a production cutover.

The recovery script creates a randomly named PostgreSQL 16 container with no
network, inserts a probe row, writes a custom-format `pg_dump`, drops the probe,
restores it, reads it back, and always removes the container and temporary dump.
It never uses the project volumes or a production database. Docker is required;
if Docker is unavailable the gate is reported as blocked rather than replaced
with an unverified claim.

## Staging Compose validation

`deploy/staging/compose.yaml` uses distinct named volumes and credentials from
production. Keep `deploy/staging/.env` untracked. Validate without displaying
resolved secrets:

```sh
STAGING_POSTGRES_PASSWORD='local-only' \
STAGING_JWT_SECRET='local-only-long-secret-012345678901234567890123' \
STAGING_CORS_ORIGINS='["http://localhost:8091"]' \
  docker compose -f deploy/staging/compose.yaml config --quiet
```

If staging is started manually, verify `docker compose ps` reports healthy
PostgreSQL, API, and Web, then test the Web origin's `/api/` route and a file
just above/below the 10 MiB application limit. Tear down only the isolated stack
with `docker compose --env-file .env down -v` after verification.

## Release safety

Android release configuration now refuses APK/AAB configuration unless all four
explicit environment variables are supplied by a protected release runner:
`FARM_RELEASE_STORE_FILE`, `FARM_RELEASE_STORE_PASSWORD`,
`FARM_RELEASE_KEY_ALIAS`, and `FARM_RELEASE_KEY_PASSWORD`. Do not add those
values to git, CI logs, `.env` files, or this repository. No signing key is
created or changed by Phase 5. Web release builds must retain
`--dart-define=FARM_API_BASE_URL=/`; production Web state is not changed by
these gates.

GitHub Actions runs the staging model and isolated recovery gate after the
existing backend and Flutter jobs. A successful CI run is validation only; it
is not authorization to deploy, publish, or sign.

# PostgreSQL API migration

## Run locally
1. Copy `.env.example` to `.env` and replace every secret.
2. `docker compose config --quiet`
3. `docker compose up -d --build`
4. Open `http://localhost:8000/docs`; verify `GET /health` returns `{"status":"ok","database":"ok"}`.

The API is the only public data boundary. PostgreSQL binds to localhost and is not exposed to the network.

## Migration status
- Backend: PostgreSQL schema, JWT auth, owner-scoped resources, finance/fuel/tasks/settings and reports — implemented.
- Flutter: original farmer-main navigation and API-backed CRUD UI for plots, cycles, activities, finance, fuel, schedules and category settings — implemented and verified locally.
- Partial: attachments/image upload and offline queue require additional API work; push delivery is implemented with a durable outbox.
- Firebase packages, active imports and Android/Firebase project configuration have been removed. No Firebase data is imported.

## Push delivery contract
Push outbox delivery is at-least-once: a worker restart can resend a payload after a provider accepts it. Each task reminder payload therefore includes its stable `notificationId`. The `/push/` service worker stores presented IDs in IndexedDB and suppresses repeats, while retaining the payload `url` in notification data for click navigation. IDs are scoped to the browser's push worker database; changing or clearing browser storage may allow a presentation again.

## Safe Phase 5 release gates
Reproducible staging Compose validation, clean Web release checks, isolated PostgreSQL backup/restore, upload/proxy checks, and Android signing safeguards are documented in [`docs/phase5-release-gates.md`](docs/phase5-release-gates.md). These checks do not deploy Production or create signing keys.

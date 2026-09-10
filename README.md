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
- Partial: attachments/image upload, push notifications and offline queue require additional API work.
- Firebase packages, active imports and Android/Firebase project configuration have been removed. No Firebase data is imported.

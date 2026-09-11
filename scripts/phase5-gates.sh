#!/usr/bin/env bash
# Safe Phase 5 gates: no production deployment or signing-key access.
set -Eeuo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

compose_gate() {
  command -v docker >/dev/null 2>&1 || { echo "SKIP: docker unavailable (compose validation)"; return 0; }
  docker compose version >/dev/null 2>&1 || { echo "SKIP: docker compose unavailable"; return 0; }
  STAGING_POSTGRES_PASSWORD=phase5-compose-check-only \
  STAGING_JWT_SECRET=phase5-compose-check-only-012345678901234567890123 \
  STAGING_CORS_ORIGINS='["http://localhost:8091"]' \
    docker compose -f deploy/staging/compose.yaml config --quiet
  echo "PASS: staging Compose resolves without printing secrets"
}

proxy_gate() {
  grep -Eq 'client_max_body_size[[:space:]]+12m;' deploy/staging/nginx.conf
  grep -Eq 'proxy_pass[[:space:]]+http://api:8090;' deploy/staging/nginx.conf
  grep -Eq 'ATTACHMENT_STORAGE_PATH' deploy/staging/compose.yaml
  grep -Riq '10[[:space:]]*\*\*?[[:space:]]*2\|10[[:space:]]*MiB\|10_?485_?760' backend/app backend/tests
  echo "PASS: staging proxy and 10 MiB upload contract are present"
}

release_safety_gate() {
  if git ls-files | grep -E '(^|/)([^/]+\.(jks|keystore|p12|pem|key))$' >/dev/null; then
    echo 'FAIL: signing material is tracked' >&2; return 1
  fi
  grep -q 'Refusing release APK/AAB without explicit signing properties' android/app/build.gradle.kts
  grep -q 'FARM_API_BASE_URL=/' .github/workflows/ci.yml
  echo "PASS: signing and production Web API safety gates are present"
}

web_gate() {
  if [[ "${SKIP_FLUTTER_BUILD:-0}" == 1 ]]; then
    echo "SKIP: Flutter Web build requested off"
    return 0
  fi
  command -v flutter >/dev/null 2>&1 || { echo "SKIP: flutter unavailable (Web build)"; return 0; }
  flutter clean
  flutter pub get
  flutter build web --release --dart-define=FARM_API_BASE_URL=/
  test -s build/web/index.html
  ! grep -R '192\.168\.1\.213:8090' build/web
  echo "PASS: clean Web release build uses same-origin API"
}

case "${1:-all}" in
  all) compose_gate; proxy_gate; release_safety_gate; web_gate ;;
  compose) compose_gate; proxy_gate; release_safety_gate ;;
  web) web_gate ;;
  *) echo "usage: $0 [all|compose|web]" >&2; exit 2 ;;
esac

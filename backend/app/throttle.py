import hashlib
from datetime import datetime, timezone, timedelta
from fastapi import HTTPException
from sqlalchemy import text
from app.database import engine, settings

def throttle(request, email):
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(seconds=settings.auth_rate_window_seconds)
    keys = sorted(hashlib.sha256(value.encode()).hexdigest() for value in ('ip:' + request.client.host, 'email:' + email))
    counts = []
    with engine.begin() as conn:
        conn.execute(text('DELETE FROM auth_throttles WHERE window_start < :cutoff'), {'cutoff': now - timedelta(days=1)})
        for key in keys:
            counts.append(conn.execute(text("""INSERT INTO auth_throttles (key, window_start, attempts)
                VALUES (:key, :now, 1) ON CONFLICT (key) DO UPDATE SET
                attempts = CASE WHEN auth_throttles.window_start <= :cutoff THEN 1 ELSE auth_throttles.attempts + 1 END,
                window_start = CASE WHEN auth_throttles.window_start <= :cutoff THEN :now ELSE auth_throttles.window_start END
                RETURNING attempts"""), {'key': key, 'now': now, 'cutoff': cutoff}).scalar_one())
    if max(counts) > settings.auth_rate_limit:
        raise HTTPException(429, 'Too many authentication attempts', headers={'Retry-After': str(settings.auth_rate_window_seconds)})

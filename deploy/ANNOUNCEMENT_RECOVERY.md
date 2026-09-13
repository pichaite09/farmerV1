# Announcement FCM recovery — NEW ONLY rollout authorized

## Binding rollout contract (2026-09-13)

The user authorizes NEW announcements only. NEVER reset, resend, recreate, or
release historical campaigns, including pre-activation drafts. Migration 0025
persists an immutable cutoff greater than all existing announcement/notice times.
Missing policy fails closed; inbox history and task reminders remain unaffected.

Independent review found a direct `send_to_owner` bypass and a migration race.
The direct helper now requires an eligible persisted owner notification, refuses
unknown IDs, and uses persisted content. Its historical regression was observed
RED (six provider-call failures) before the fix. Deployment MUST stop and verify
both OLD API and scheduler before migration. Table locks alone are not sufficient.

Use `deploy/activate_notifications.py` on the host in separate phases:
1. After protected backups, transfer verified source and prepare/build the image
   while the old API stays available; keep scheduler stopped.
2. Only after isolated targeted/full tests and independent review pass, activate:
   quiesce old API/scheduler and confirm no extra replicas, snapshot historical
   data, migrate, force-recreate API, await readiness. This is the short downtime.
3. Read back cutoff/head and historical exclusion, then explicitly start worker
   from the identical image. Compare the pre-activation historical digests with
   post-activation and post-worker-cycle digests. Never probe real providers.
4. Separately force-recreate Web after replacing the verified built artifact;
   verify origin/public assets and hashes. Do not touch legacy :8080.

The older sections below record the original diagnosis, not permission to replay.
The binding new-only contract and executable quiescence gate supersede their
original draft procedure. Rollout evidence: `/root/farmer-main-rollout-evidence/`.


## Verified diagnosis (2026-09-12 UTC)

Production inspection was read-only. API `ba99696c0c44` is current; scheduler
`c6a79e3c88af` was created 2026-09-11 and remains an orphan: deployed Compose lists
only postgres/api. Its image lacks `app/fcm.py`; its delivery implementation always
looks up a Web Push subscription even for FCM rows (whose subscription_id is NULL),
then raises ValueError. It also has none of the three FIREBASE_* variables and is
attached only to the internal private network, unlike the API's private+edge.
Adding credentials alone or restarting this image cannot fix the delivery path.

SHA256 of app/push.py:
- current API: 5d5a6acc5cc431b8e94f312025524c6ad5b6a26520d1225373e6a200a579cb58
- old scheduler: 9ddaf362431e10bc22def76c604e2f2847fb04933cb937a91c3d1095cc37ebd9

Read-only initial queue snapshot (changing while old worker runs):
- Announcements: sending=2, completed=3; no drafts.
- Recipients: pending=2, failed=1, suppressed=7.
- FCM outbox: pending=2 (ValueError, attempts 2/3); failed suppressed=4.
- Web outbox: pending=2 (RuntimeError, attempts 2/3), failed suppressed=2,
  failed RuntimeError=1 (attempts=5).
- Active device records=1; inactive=7. Migration=0024_announce_attach.
Counts are delivery rows, not distinct recipients; they are not a replay plan.

## Final read-back and verification

At 2026-09-12 15:26:38 UTC the unchanged old worker had naturally exhausted the
remaining retries: announcements completed=5; FCM failed ValueError=2 and
suppressed=4; Web failed RuntimeError=3 and suppressed=2. No pending rows remained.
No operator queue writes or production restarts were performed. Production API,
scheduler and Web IDs remained ba99696c0c44, c6a79e3c88af and 56b2563c629a.
Thus a new worker alone cannot recover these terminal FCM failures. Recovery needs
an explicitly approved, scoped decision that avoids duplicate historical sends.

Verified in rebuilt isolated staging API b70820c450e3:
- announcement/admin-FCM/device suites: 19 passed (134.77s).
- push/delivery/scheduler suites: 17 passed (135.75s).
- staging cleanup read-back: users=0, announcements=0, outbox=0; healthy API.
- deployment regression: RED for missing scheduler, then 1 passed; rendered Compose
  with notifications profile validates using dummy values only.
- Flutter status regression: RED for absent queued label, then GREEN.
- full Flutter suite: 45 passed; analyze: no issues; release Web build succeeded
  at build/web (not deployed); no APK created.
- full backend suite was attempted but tool transport timed out at 420s while
  remote pytest continued. That exact test process was stopped before running
  serial targeted suites. Full-backend acceptance is NOT claimed; rerun using
  deploy/verify_staging_notifications.py with durable logging/long-running job
  tracking before release. No test process was left running.
- SDK deprecation warnings remain in Python tests; no real FCM/device delivery
  acceptance and no production rollout were performed.

## Local changes

Root Compose explicitly defines an opt-in `notifications` profile worker sharing
API image/build, database/Firebase environment and provider egress. A healthy API
migration gates startup. Profile does NOT stop an already-running old worker.
Always rebuild and recreate API AND worker together after future backend changes;
an explicit image tag alone does not refresh a running container.

Flutter now distinguishes draft/queued/sending/sent/completed/cancelled and the
Sent filter includes only actual `sent`. Backend `sent` means at least one provider
accepted delivery, NOT every recipient received it or Android displayed it.

## Superseded recovery proposal

The original backlog-recovery proposal was NOT executed and is no longer
permitted. Use only the binding NEW-ONLY contract above and the executable
activation script. No historical cancellation, retry reset, release, recreation,
or real-device probe is authorized. Preserve existing inbox/history rows.

## Regression reproduction

The new end-to-end test sends a synthetic selected-user announcement through API,
PushOutbox, scheduler, actual FCM adapter, with only Firebase SDK send/init mocked.
Substituting the production worker's old deliver_claimed implementation in the
isolated staging test process fails `(0, 0) != (1, 0)` and logs ValueError. No
production function is invoked. No real FCM network send is required.

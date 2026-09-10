# Phase 7 — Backups และ Production Cutover

วันที่: 2026-09-09

## Cutover

- Production Web ใหม่: `http://192.168.1.213:8081`
- Production API: `http://192.168.1.213:8090`
- Production Web stack: `/opt/stacks/farmer-main-production`
- ใช้ nginx same-origin proxy `/api/*` ไป API `8090`
- Web build ใช้ API origin ของหน้าเว็บ ไม่ฝัง private API IP
- Web เดิม `farm-mobile-web` ถูกหยุดและตั้ง `restart=no` เพื่อ rollback ได้ทันที

## Backups

ก่อน cutover:

- `/opt/stacks/farmer-main/backups/pre-cutover-20260909T045644Z.dump` — 29,402 bytes
- `/opt/stacks/farmer-main/backups/source-pre-cutover-20260909T045644Z.tgz` — 101,630 bytes
- `/opt/stacks/farmer-main/backups/legacy-web-20260909T045644Z.tgz` — 14,064,533 bytes
- `/opt/stacks/farmer-main/backups/legacy-web-20260909T045644Z.inspect.json`

หลัง cutover:

- `/opt/stacks/farmer-main/backups/post-cutover-20260909T045939Z.dump` — 29,449 bytes
- `/opt/stacks/farmer-main/backups/source-post-cutover-20260909T045939Z.tgz` — 101,630 bytes

## Restore verification

- Restore pre-cutover dump เข้า isolated database ผ่าน
- migration head: `0004_attachments`
- อ่าน schema/counts หลัง restore ได้สำเร็จ
- ไม่มีการลบข้อมูลจริง; dump พบ `users=1, plots=1` เป็นบัญชี/ข้อมูลจริงของผู้ใช้

## Production verification

- Production Web container: healthy
- API `/health`: `{"status":"ok","database":"ok"}`
- CORS preflight origin `8081`: `200`
- register ผ่าน production proxy: `201`
- authenticated dashboard ผ่าน production proxy: `200`
- dashboard route `/api/v1/dashboard` คืนข้อมูล owner-scoped
- production bundle SHA-256 ตรงกับ local:
  `667795cb874e76e7e5591268d35588d21b07a4b8ab825ad75266d79759add809`
- API migration head: `0004_attachments`
- API UID: `10001`
- PostgreSQL ไม่มี published host port

## Legacy safety

- `farm-api` เดิมยัง ID `dd292f9404ab`, port `8080`
- `farm-postgres` เดิมยัง ID `12112cfe22da`
- ระบบเดิม API/PostgreSQL ไม่ถูกหยุดหรือแก้ไข
- `farm-mobile-web` เดิมถูกหยุดเฉพาะเพื่อ cutover Web `8081`; backup และ inspect file พร้อม rollback

## Remaining limitation

- Browser interactive automation ใน Hermes environment ยังถูกจำกัดโดยไม่มี Chromium/GUI; production HTTP, proxy, auth, dashboard, health และ asset hash ผ่านแล้ว
- Internet access ควรใช้ HTTPS ก่อนส่งรหัสผ่านจริง

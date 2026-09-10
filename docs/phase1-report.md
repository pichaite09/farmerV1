# ระยะ 1 — PostgreSQL + Authentication

## ส่งมอบและตรวจจริง
- Stack ใหม่ `/opt/stacks/farmer-main` บน `192.168.1.213` แยกจากสมุดไร่นา
- API `http://192.168.1.213:8090` และ Swagger `/docs`
- PostgreSQL 16; named volume `farmer_main_postgres_data`; ไม่มี host port ฐานข้อมูล; private Docker network
- Alembic revision `0001_auth`: users, sessions, auth_throttles และ alembic_version; upgrade ซ้ำผ่าน
- API รัน UID 10001; `.env` remote mode 600; ไม่มี default account; secrets ถูกหมุนใหม่หลังคำสั่งตรวจรอบหนึ่งแสดง environment โดยไม่ตั้งใจ
- `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, `GET /api/v1/auth/me`, `POST /api/v1/auth/logout`
- สมัครด้วย email/password, password 8–200 ตัวอักษร, email normalize lower-case, hash Argon2id; farmer-only role ทั้ง API/DB
- JWT HS256 อายุเริ่มต้น 1800 วินาที ต้องมี sub/jti/iat/nbf/exp/iss/aud; DB sessions ตรวจ ownership/expiry/revocation ทุกครั้ง
- Logout ยกเลิกเฉพาะ session ปัจจุบัน; error contract ไม่คืน password
- PostgreSQL-backed atomic throttle: IP + email ร่วม login/register 10 ครั้ง/300 วินาที; ไม่เชื่อ X-Forwarded-For; cleanup window เก่าเมื่อมี auth request
- Health `/health/live`, `/health/ready`, `/health`; CORS จำกัด `http://192.168.1.213:8091`

## หลักฐาน
- `final-tests.log`: 33 passed, 2 dependency deprecation warnings; PostgreSQL จริงฐาน `farmer_main_test`, ไม่มี SQLite/mock DB
- ทดสอบ signup/hash, duplicate email, wrong password, role/owner injection, missing/malformed/expired/forged/future JWT, issuer/audience/algorithm, unknown/mismatched session, logout isolation, DB role constraint, concurrent throttle และ forwarded-header bypass
- HTTP จาก Hermes: register/login/me/logout สองบัญชี ผ่าน; token ที่ logout แล้วได้ 401 โดย session อีกชุดยังใช้งานได้
- Recreate PostgreSQL/API: user และ session คงอยู่; logout แล้ว restart API: token เดิมยังได้ 401
- `cleanup.log`: ลบบัญชีทดสอบจริงด้วย 4 exact UUID; runtime users=0, sessions=0; ไม่มี Firebase import
- หลังหมุน secrets: recreate healthy, tests 33 ผ่านซ้ำ และ independent HTTP health/auth checks ผ่าน
- `final-infrastructure-readback.log`: PostgreSQL ไม่มี published port, API UID 10001, .env 600, volume mount และระบบเดิม
- ระบบเดิม IDs: farm-mobile-web b871fd4fe44c, farm-api dd292f9404ab, farm-postgres 12112cfe22da ไม่เปลี่ยน
- SHA-256 bundle เดิม: `179d9ca26b2e1dc3eb954a0f55c98bc673170e1b473523e6109073d3e21e4d43` ไม่เปลี่ยน; API เดิม health OK
- Backup ก่อนปรับ backend: `/opt/stacks/farmer-main/backups/pre-phase1-finish.dump`

## ยังไม่รวม / ข้อจำกัด
- ยังไม่เชื่อม Flutter UI, ไม่เปลี่ยน Web 8081 และยังไม่มี Web ใหม่ 8091
- ยังไม่มี CRUD แปลง/รอบผลิต/การเงิน: สิทธิ์ระยะนี้ตรวจ identity/session; cross-owner resource CRUD ต้องทดสอบในระยะถัดไป
- ไม่มี admin, email verification, password reset, refresh token, automatic backup schedule หรือ HTTPS ในระยะนี้
- HTTP 8090 เหมาะกับ staging บนเครือข่ายที่เชื่อถือได้เท่านั้น; ต้องเพิ่ม HTTPS/firewall ก่อนใช้รหัสผ่านจริงผ่าน Internet
- Rate limit เป็น fixed window; ผู้ใช้หลัง NAT เดียวกันแชร์ IP quota
- SSH key คงไว้ตามคำสั่งผู้ใช้

## รันทดสอบซ้ำบน Docker host
ใช้ฐานทดสอบเท่านั้น (fixture ป้องกันชื่อฐานผิดและ truncate เฉพาะ test DB):
```sh
cd /opt/stacks/farmer-main
docker compose run --rm -T api sh -c 'export DATABASE_URL="${DATABASE_URL%/farmer_main}/farmer_main_test"; alembic upgrade head && python -m pytest -q -p no:cacheprovider'
docker compose ps
curl -fsS http://127.0.0.1:8090/health/ready
```
อย่าใช้ `docker compose config` แบบแสดงเต็มหรือคำสั่ง `export` ที่ไม่มี arguments เพราะอาจแสดง secrets; ใช้ `docker compose config --quiet`.

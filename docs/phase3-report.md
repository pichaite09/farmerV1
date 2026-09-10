# ระยะ 3 — การเงิน เชื้อเพลิง ตารางงาน และตัวเลือก

## สิ่งที่เพิ่ม
- Alembic `0003_phase3` (migration-safe; upgrade ซ้ำสำเร็จ)
- ตาราง `transactions`, `vehicles`, `fuel_records`, `tasks`, `category_settings`
- owner-scoped CRUD พร้อม strict camelCase schemas และ validation
- linked transaction/fuel one-to-one, atomic sync/delete, standalone fuel ไม่สร้าง transaction
- finance/fuel reports แบบ server-side และ inclusive date filters
- category defaults จาก source, trimmed unique whitelist และ If-Match version conflict

## Verification จริง
- PostgreSQL isolated database `farmer_main_test`: `alembic upgrade head` ซ้ำ และ **37 passed, 3 warnings**
- production migration: `0003_phase3`; API health `200`, OpenAPI `200` มี phase3 routes; tables ครบ
- deployment stack `farmer-main-api-1` healthy บน `8090`
- old containers unchanged: `farm-mobile-web=b871fd4fe44c`, `farm-api=dd292f9404ab`, `farm-postgres=12112cfe22da`
- pre-deploy backups: custom-format DB dump และ source tar ที่ `/opt/stacks/farmer-main/backups/`

## หมายเหตุ
- Flutter/UI ยังไม่ได้แก้ตามขอบเขต backend-only
- local PostgreSQL ไม่เปิด จึงรัน integration suite บน isolated PostgreSQL ของ deployment host แทน
- ไม่รวม secrets ใน source package

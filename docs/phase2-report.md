# ระยะ 2 — แปลง → รอบผลิต → กิจกรรม

## สิ่งที่เพิ่ม
- Alembic migration `0002_phase2_resources`
- ตาราง PostgreSQL: `plots`, `production_cycles`, `activities` พร้อม FK, index, check constraints
- Owner-scoped CRUD API:
  - `GET/POST /api/v1/plots`
  - `GET/PATCH/DELETE /api/v1/plots/{id}`
  - `GET/POST /api/v1/cycles`
  - `GET/PATCH/DELETE /api/v1/cycles/{id}`
  - `GET/POST /api/v1/activities`
  - `GET/PATCH/DELETE /api/v1/activities/{id}`
- JSON ใช้ camelCase ตาม contract
- Pagination `limit/offset` และ filter `cycleId` สำหรับกิจกรรม
- ตรวจ owner chain ทุก create/update/get/delete; owner อื่นตอบ 404 แบบเดียวกับ resource ที่ไม่มี
- ลบ plot ที่มี cycle และ cycle ที่มี activity ตอบ 409 ไม่ cascade
- กิจกรรม `completeCycle=true` ปิดรอบผลิตแบบ transaction เดียว; กิจกรรมภายหลังในรอบที่ปิดแล้วตอบ 409
- ห้าม client เขียน `imageUrl` โดยตรง; คงไว้สำหรับ attachment ระยะถัดไป

## ผลตรวจจริง
- Migration upgrade เป็น `0002_phase2_resources`; ตรวจ rerun สำเร็จ
- ชุดทดสอบ PostgreSQL จริง: **37 passed, 2 warnings**
- Independent live HTTP test ผ่าน:
  - ผู้ใช้ A/B แยกข้อมูลจริง
  - A สร้าง/อ่าน/แก้ไข plot
  - รอบผลิต derive `plotName`
  - B ใช้ plot/cycle ของ A ไม่ได้
  - สร้าง activity และ harvest ปิด cycle
  - activity หลัง cycle ปิดตอบ 409
  - ลบ parent ที่มี child ตอบ 409
- หลัง cleanup: `users=0`, `plots=0`, `cycles=0`, `activities=0` ในฐาน production ใหม่
- API และ PostgreSQL healthy; API รัน UID 10001
- Backup ก่อน final phase2: `/opt/stacks/farmer-main/backups/pre-phase2-final.dump` ขนาด 13,502 bytes
- ระบบเดิมไม่เปลี่ยน: containers `farm-mobile-web b871fd4fe44c`, `farm-api dd292f9404ab`, `farm-postgres 12112cfe22da`; Web SHA-256 เดิมยังตรง

## ข้อจำกัด
- ยังไม่เชื่อม Flutter/UI
- ยังไม่มีรูปภาพ/attachments, dashboard, การเงิน, เชื้อเพลิง, task หรือ offline queue
- ยังไม่ได้เปิด production web port 8091
- `status=completed` เปิดกลับเป็น `active` ได้ด้วย cycle PATCH ตาม contract; activity ไม่ reopen อัตโนมัติ

## Artifact
- source package ระยะ 2: `/root/farmer-main-phase2.zip`

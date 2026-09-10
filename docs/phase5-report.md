# Phase 5 — รูปภาพและ Offline

วันที่: 2026-09-09

## Backend รูปภาพ

- เพิ่ม migration `0004_attachments` ต่อจาก `0003_phase3`
- เพิ่ม persistent Docker volume `farmer_main_attachment_data` ที่ `/data/attachments`
- เพิ่ม authenticated endpoints:
  - `POST /api/v1/attachments`
  - `GET /api/v1/attachments?parentType=&parentId=`
  - `GET /api/v1/attachments/{id}/content`
  - `DELETE /api/v1/attachments/{id}`
- ตรวจ owner chain สำหรับ plot/activity
- ตรวจ extension และ file signature: JPEG/PNG/WebP
- จำกัดขนาดไม่เกิน 10 MiB
- ใช้ random storage filename ไม่ใช้ชื่อไฟล์จากผู้ใช้
- จำกัดรูปหลักหนึ่งรายการต่อ parent และ replace แบบไม่ลบรูปเก่าก่อน upload ใหม่สำเร็จ
- content ต้องใช้ Bearer authentication

## Flutter Offline

- เพิ่ม multipart attachment client สำหรับ `image_picker` ทั้ง Web/mobile
- upload รูปเป็น online-only และไม่ใส่ใน JSON offline queue
- ตรวจขนาด/ชนิดไฟล์เบื้องต้นก่อนส่ง
- เชื่อม upload กับ plot/activity UI
- เพิ่ม offline JSON queue แยก storage key ต่อ authenticated user
- network write failure ถูก queue และ replay พร้อม Authorization + idempotency key
- ไม่ queue HTTP `401/403/422`; รายการถูกเก็บเป็น blocked เพื่อแก้ไขก่อน retry
- queue replay ตอน restore session และสั่ง sync ได้จาก UI

## Verification

- Backend isolated PostgreSQL suite: **40 passed, 3 warnings**
- Flutter `flutter analyze`: ผ่าน ไม่มี issues
- Flutter `flutter test`: **17 tests passed**
- Flutter Web release build พร้อม `FARM_API_BASE_URL=http://192.168.1.213:8090`: ผ่าน
- Live API upload flow: register → create plot → upload PNG → list → authenticated content → delete → list empty: ผ่าน
- Live CORS preflight สำหรับ attachment POST: `200` พร้อม allow-origin ที่กำหนด
- Production migration head: `0004_attachments`
- API health: `{"status":"ok","database":"ok"}`
- API container: healthy, UID `10001`
- PostgreSQL: healthy, ไม่มี published host port
- Attachment volume: `farmer_main_attachment_data:/data/attachments`
- หลัง cleanup ข้อมูลทดสอบ: users/plots/attachments เป็นศูนย์
- ระบบเดิมตรวจแล้วคงเดิม: `farm-api` `dd292f9404ab`, `farm-mobile-web` `b871fd4fe44c`, `farm-postgres` `12112cfe22da`

## Backup

- `/opt/stacks/farmer-main/backups/pre-phase5-20260909T035453Z.dump`
- `/opt/stacks/farmer-main/backups/pre-phase5-fix-20260909T035635Z.dump`
- source backups อยู่ใน directory เดียวกัน โดยไม่รวม `.env`

## ข้อจำกัด

- ยังไม่ได้ deploy Flutter Web ไป production `8081`
- ไม่ได้ทดสอบกล้องจริงบนอุปกรณ์มือถือ; multipart boundary, validation และ online-only behavior ผ่าน automated tests
- Offline queue ยังเป็น explicit sync/session-restore ไม่ใช่ background connectivity listener
- Push/background notifications และ offline binary photo queue ยังไม่ implement; รูปต้อง upload ตอนออนไลน์
- ใช้งานผ่าน Internet ยังควรเพิ่ม HTTPS ก่อนใช้จริง

# Phase 6 — Staging แยกและ browser verification

วันที่: 2026-09-09

## Staging

- สร้าง stack แยกที่ `/opt/stacks/farmer-main-staging`
- Web URL: `http://192.168.1.213:8091`
- ใช้ image `nginx:1.27-alpine`
- API target ของ build: `http://192.168.1.213:8090`
- ไม่ใช้ฐานข้อมูลหรือ container ของ `farm-data-system`
- Compose source เก็บใน `deploy/staging/compose.yaml`

## ตรวจด้วย tool

- `docker compose config --quiet`: ผ่าน
- staging container: `healthy`
- `GET /` ที่ `8091`: ผ่าน
- `GET /flutter.js`/main bundle: ผ่าน
- local-to-remote main bundle SHA-256 ตรงกัน:
  `d3f54e4adbf7ccfdfdd03ca18873265f4caf596dc02733e0819e0b68335ebd51`
- API `GET /health`: `{"status":"ok","database":"ok"}`
- Preview เปิด URL ได้และ title เป็น `เกษตรกร`
- API CORS preflight จาก origin `8091`: ผ่านจากการตรวจระยะ 5
- แก้ login connection failure: staging build ใช้ same-origin API และ nginx proxy `/api/` ไป API `8090`; preflight ผ่าน `200` และ POST login ผ่าน proxy ถึง API ได้
- staging bundle ล่าสุดไม่ฝัง `192.168.1.213:8090` แบบ hard-coded

## Browser limitation

Browser automation แบบ Chromium และ desktop screenshot ใช้งานไม่ได้ใน Hermes environment นี้:

- browser tool ปฏิเสธเพราะ default profile ไม่ใช่ Chromium ที่รองรับ
- ไม่มี `$DISPLAY` หรือ `$WAYLAND_DISPLAY` สำหรับ cua-driver
- Flutter Web canvas ใน preview ไม่ส่ง interactive accessibility elements จึงไม่สามารถกรอก login/คลิก CRUD จริงผ่าน driver ได้

ดังนั้นระยะ 6 ยืนยันได้ถึง static serving, title, bundle integrity, API health, same-origin proxy และ CORS; ยังไม่มีหลักฐาน browser interaction แบบคลิก/กรอกจริงของ CRUD/offline sync เพราะ environment ไม่มี GUI/Chromium driver.

## Scope safety

- Web เดิม `8081` ไม่ถูกเปลี่ยน
- API เดิม `8080` ไม่ถูกเปลี่ยน
- `farm-data-system` ไม่ถูกแตะ
- ไม่มีข้อมูลผู้ใช้/ธุรกรรมตัวอย่างในฐานใหม่

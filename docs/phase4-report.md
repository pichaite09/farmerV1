# Phase 4 — Restore UI และย้ายออกจาก Firebase

วันที่: 2026-09-09

## ผลงาน

- คืนโครง UI หลักของ `farmer-main` จาก baseline ZIP ต้นฉบับ ไม่ใช้ UI ของ `farm-data-system`
- เปลี่ยน active Flutter data/auth path เป็น FastAPI/PostgreSQL ผ่าน `FarmerApi` และ `ApiSession`
- ลบ Firebase packages และ active Firebase imports จาก Flutter
- ลบ Firebase Android Gradle plugin, `firebase.json` และ `android/app/google-services.json`
- เพิ่ม API-backed CRUD UI สำหรับ:
  - แปลง, รอบผลิต, กิจกรรม และ harvest `completeCycle`
  - รายการการเงินและสรุปตามวัน/เดือน/ปี
  - ยานพาหนะและเชื้อเพลิง
  - ตารางงานและสถานะงาน
  - ตัวเลือกหมวดหมู่พร้อม `If-Match` conflict handling
- ใช้ `FARM_API_BASE_URL` ผ่าน `--dart-define`; ค่าเริ่มต้นสำหรับ local dev คือ `http://localhost:8090`
- ไม่สร้างข้อมูลตัวอย่างและไม่เขียน `imageUrl` แบบเงียบ ๆ

## Verification

ตรวจจากสำเนา workspace ที่ไม่ใช่ root user:

- `flutter pub get` ผ่าน
- `flutter analyze --no-fatal-infos --no-fatal-warnings` ผ่าน ไม่มี issues
- `flutter test` ผ่าน 9 tests
- `flutter build web --release --dart-define=FARM_API_BASE_URL=http://192.168.1.213:8090` ผ่าน
- ตรวจ static web artifact ด้วย HTTP server local: `index.html` และ `flutter.js` ตอบสำเร็จ
- ค้นทั้ง repository ไม่พบ Firebase active configuration/import หลังลบ Android/Firebase config

## ข้อจำกัดที่ยังเหลือ

- Attachments/image upload ยังไม่เปิดใช้งาน เพราะ API attachments ยังไม่ถูกสร้าง; UI แจ้งเป็น partial อย่างชัดเจน
- Push/background notifications และ offline queue ยังไม่ implement
- ยังไม่ได้ deploy ไป production `8081`; ระบบเดิมและ UI production จึงไม่ถูกเปลี่ยน
- Browser automation ใน environment นี้เปิดไม่ได้เพราะ default browser ไม่ใช่ Chromium ที่รองรับ จึงใช้ Flutter build และ HTTP static smoke test แทน

## ขอบเขตที่ไม่ถูกแตะ

- `farm-data-system`, API `8080`, Web `8081`
- Firebase remote project และข้อมูล Firebase เดิม — ไม่มีการ import/migrate ข้อมูลเดิมตามคำสั่งผู้ใช้

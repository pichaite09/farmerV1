# FarmerV1 System Audit & Improvement Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** ปรับความถูกต้องของข้อมูล ความปลอดภัย ความเสถียร และเลย์เอาต์ โดยรักษาหน้าตาและข้อมูล Production เดิม

**Architecture:** คง Flutter + Provider → FastAPI → PostgreSQL แยก business services, state invalidation และ attachment delivery ออกจากหน้าจอ เพิ่ม isolated staging/CI และ artifact deployment ที่ทำซ้ำได้ ไม่ rewrite ทั้งระบบ

**Tech Stack:** Flutter/Dart, FastAPI/Pydantic, SQLAlchemy/Alembic, PostgreSQL, nginx/Docker, Android Gradle

## ฐานอ้างอิงและข้อจำกัด
- ตรวจจาก commit `2637c6c6e05bbdc0561afdb00654af34df0a7b1a` วันที่ 2026-09-10
- ตรวจ inventory 256 tracked files; backend อ่าน 16 app modules, migrations 13 + env, tests 11 ไฟล์; frontend อ่าน service/หน้าหลักและ flow สำคัญ รวม tests 4 ไฟล์ ส่วน UI อื่นใช้ targeted inspection ไม่ใช่ตรวจทุกบรรทัดทุกไฟล์
- ผู้ตรวจโครงสร้างรายงาน AST parse Python 42 ไฟล์ผ่าน; เป็น syntax เท่านั้น
- รอบนี้ไม่ได้รัน Flutter/build/pytest/production mutations ไม่ใช้ผล tests รอบก่อนเป็นผล audit ปัจจุบัน ไม่ตรวจข้อมูลส่วนบุคคลจริง
- Layout findings เป็นความเสี่ยงจาก source ยังไม่ยืนยันด้วย screenshot, browser หรืออุปกรณ์จริง
- ข้อค้นพบประกอบด้วย static findings และข้อเสนอ ต้องสร้าง regression tests เพื่อยืนยันก่อนแก้
- ยังไม่แก้ source, push, deploy หรือ build APK รอบนี้ มีเพียงไฟล์แผนนี้

## ข้อกำหนดที่ต้องรักษา
1. สรุปอยู่ รอบผลิต → สรุป แยกแต่ละรอบ ไม่รวม FuelRecord/ธุรกรรมน้ำมันและรายการไม่มี cycle_id ตามความต้องการเดิม การแยกนี้ไม่ใช่ bug; ต้องอธิบายส่วนต่างจากบัญชีรวม
2. ปิดงานมีคำอธิบาย รูปหลายรูป ยกเลิก/บันทึก; ยกเลิกไม่เปลี่ยนสถานะ
3. owner scoping ทุก API/รูป; ห้ามเปิดเผย secrets
4. Staging แยก API/DB/volume และใช้ข้อมูลจำลองเท่านั้น; ไม่ใช้ Production fixture ที่ TRUNCATE
5. Backup DB + attachments + web ก่อน migration/deploy; ไม่แตะ Legacy API :8080
6. ไม่เพิ่ม AI planning ไม่สร้าง APK ไม่ deploy จนได้รับอนุมัติการดำเนินงาน
7. คงภาษาไทย Date Picker พ.ศ., AppBar เต็มกว้าง มุมบนฉาก และหน้าตาหลักเดิม

## Findings และลำดับความสำคัญ

### P1: ข้อมูลสูญหาย/ตัวเลขผิด/ความปลอดภัย
| ID | หลักฐาน | ผลกระทบและงานที่เสนอ |
|---|---|---|
| D1 | backend/app/reports.py:31–43 | Dashboard รวม transaction แล้วบวก fuel อีกครั้ง และ fuel ถูก limit 10 ก่อนรวมยอด เสี่ยงนับ linked fuel ซ้ำและยอดไม่ครบ แยก aggregate กับ recent query |
| D2 | backend/app/phase3.py:65–75 | แก้ transaction โดยไม่ส่ง fuel ทำให้ amount/date/type ไม่สอดคล้อง linked fuel กำหนด ledger source of truth |
| O1 | lib/services/offline_queue.dart:117–159 | enqueue/flush อ่านและเขียน snapshot ทั้งชุด อาจทับรายการใหม่หรือ replay พร้อมกัน ต้อง serialize/transactional removal |
| O2 | lib/services/api_session.dart:37–43,88–94 | restore จับ network error แล้ว logout ต้องแยก network failure/401 และกำหนด offline session policy |
| O3 | lib/screens/schedule_screen.dart:377–401; lib/services/farmer_api.dart:45–47,75–93 | queued mutation ถูกแสดงเป็น failure ส่งซ้ำด้วย key ใหม่ได้ ต้องมีสถานะรอซิงค์และ logical submission ID |
| A1 | lib/screens/schedule_screen.dart:68–82; lib/screens/field_inspections_screen.dart:55–77 | entity สำเร็จแต่รูป upload ล้มเหลว/ถูกข้ามออฟไลน์ ต้องเก็บ per-file status และ retry โดยไม่สร้าง entity ซ้ำ |
| S1 | backend/app/schemas.py:195–205; backend/app/push.py:42–63,83–123 | push endpoint/key ไม่ validate, ไม่มี timeout/exception boundary เสี่ยง SSRF/worker failure ยังไม่ได้พิสูจน์ exploit network |
| N1 | backend/app/notifications.py:48,65; backend/app/scheduler.py:27–29,58–65 | GET สร้าง reminder ก่อน worker หรือ crash หลัง commit อาจทำให้ push หาย; concurrent workers อาจส่งซ้ำ ต้อง durable outbox |
| R1 | android/app/build.gradle.kts:35–39 | Release ใช้ debug signing ต้องวางแผน certificate continuity ก่อนเปลี่ยน ไม่เช่นนั้นอัปเดต APK เดิมทับไม่ได้ |
| R2 | deploy/staging/nginx.conf:7–8; deploy/production/nginx.conf:7–8 | tracked staging/production ชี้ :8090 เดียวกัน หาก host เดียวกันไม่แยกข้อมูล ต้องตรวจ live topology และแยกก่อนทดสอบ |

### P2: Integrity, layout และการดูแลระบบ
| ID | หลักฐาน | งานปรับปรุง |
|---|---|---|
| D3 | backend/app/schemas.py:16–48,63–95,132–150; follow_up.py:24–35 | omitted/null, max length, decimal precision ไม่สอดคล้อง DB; notes ยาวกลายเป็น task name จำกัด 200 เพิ่ม validation และไม่ truncate notes ต้นฉบับ |
| D4 | backend/app/attachments.py:142–168,186–203; models.py:117–118 | orphan attachment หลังลบ parent, cleanup หลัง commit เสี่ยงลบไฟล์ใหม่, upload race ต้อง lifecycle/cleanup job และ constraint ตาม parent type |
| D5 | resources.py:58–62; phase3.py:136–140; field_inspections.py:97–102 | ย้าย cycle/แก้ automatic task/ลบ inspection ทำให้ links ผิด กำหนด source of truth และ delete policy |
| D6 | backend/app/resources.py:43,66,77,85–88 | closed-cycle write bypass; delete dependent บางประเภทคืน 500 แทน 409 ต้องตรวจ target state/dependency ทุก write |
| D7 | backend/app/main.py:22; phase3.py:152–161 | CORS ขาด PUT; settings version check ไม่ atomic และไม่ส่ง version ต้อง CAS/ETag |
| D8 | migrations/versions/0011_field_inspections.py:39–42; 0013_task_attachments.py:19–25 | downgrade constraint อาจ fail กับข้อมูลใหม่ ต้อง rollback policy ที่ไม่ลบข้อมูลเงียบ ๆ |
| D9 | backend/app/models.py:55–56,99–101,138–139 | DB ไม่ enforce same-owner parent-child เป็น defense-in-depth gap ไม่ใช่ IDOR ที่พิสูจน์แล้ว |
| O4 | offline_queue.dart:131–155; main_screen.dart:107–119 | blocked queue ไม่มีแก้/retry/cancel รายรายการ |
| A2 | farmer_api.dart:219–229; field_inspections_screen.dart:489–500 | retry batch อาจส่งรูปที่สำเร็จแล้วซ้ำ ต้องผลรายไฟล์ |
| U1 | main_screen.dart:68–74,122–123 | เพิ่มจากปุ่มกลางแล้ว IndexedStack ไม่ invalidate หน้า/ยอด ต้อง refresh event หลัง mutation และ sync |
| U2 | schedule_screen.dart:197–200 | FutureBuilder รอบผลิตไม่มี error/retry เสี่ยง spinner ไม่จบ |
| U3 | attachment_thumbnail.dart:24–38; plots_screen.dart:130–138 | ไม่มี didUpdateWidget/key ตาม parent เสี่ยงรูปผิดหลัง reorder |
| U4 | settings_screen.dart:10–35; activities_screen.dart:147,303; schedule_screen.dart:432–440 | พ.ศ./ค.ศ./ISO แสดงต่างกัน ใช้ date display/picker กลาง เก็บ API ISO ค.ศ. |
| U5 | work_screen.dart:14–24; schedule_screen.dart:234–245,412–424 | 5 tabs ไม่เลื่อน, dropdown และ trailing แน่น เสี่ยง overflow บนจอแคบ/ตัวอักษรใหญ่ |
| U6 | schedule_screen.dart:227–237,377–378,426–429 | semantics สถานะและ validation ชื่องานไม่ครบ ต้องข้อความอ่านได้ ไม่ใช้สี/ไอคอนอย่างเดียว |
| R3 | AndroidManifest.xml:10; farmer_api.dart:27–31; compose.yaml:28 | release อนุญาต HTTP/default localhost และ API bind ทุก interface; ตรวจ TLS/proxy จริงก่อนจำกัด network |
| R4 | deploy/*/compose.yaml:8–10 | mount web artifact แต่ไม่มี clean-clone build/package pipeline |
| R5 | requirements-dev.txt เทียบ backend/requirements-dev.txt; pubspec.yaml:21–22/pubspec.lock:773–775 | dependency สองชุดต่างกัน และ SDK constraints ไม่ตรง lock ต้อง source of truth/toolchain pin |
| R6 | compose.yaml; scheduler.py:52–69 | tracked deployment ไม่มี scheduler/VAPID wiring ครบ แม้ live อาจมี ต้องเทียบโดยไม่อ่าน secret values |
| R7 | deploy/production/nginx.conf; attachments.py:19 | proxy ไม่กำหนด upload limit ให้รองรับ API 10 MiB + multipart |
| R8 | backend/tests/conftest.py:8–15; android/.gitignore; gradle-wrapper.properties | ไม่มี CI, fixture TRUNCATE, wrapper ไม่ tracked/checksum ไม่กำหนด ต้อง disposable CI และ reproducible bootstrap |
| R9 | README.md:7–14; docs/phase7-report.md:30–45 | docs ports/capabilities/restore เก่า ไม่ใช่หลักฐาน restore migration ล่าสุด |
| R10 | analysis_options.yaml:10–17; android/gradle.properties:1–2; .gitignore | global lint suppressions, JVM config ซ้ำ, ignore ยังไม่ครอบคลุม dumps/uploads/APK นอก build |

## แผนดำเนินการเป็นระยะ (รออนุมัติ)

ทุก task ใช้ลำดับ: เขียน regression test → รันให้เห็น failure → แก้ขั้นต่ำ → รัน targeted + suite → review diff/secret scan → commit เฉพาะขอบเขต ห้ามอ้างผล expected ว่าเป็นผลจริง

### ระยะ 0: สร้างฐานทดสอบปลอดภัยและ baseline
- Files: deploy/staging/compose.yaml, deploy/staging/nginx.conf, backend/tests/conftest.py, ใหม่ .github/workflows/ci.yml, docs/testing.md
- ตรวจ live topology read-only แล้วแยก staging API/DB/volume/credentials ออกจาก production อย่างชัดเจน
- Fixture ตรวจ allowlisted test DB/host และปฏิเสธ Production ก่อน TRUNCATE; disposable PostgreSQL เท่านั้น
- Pin toolchain/dependencies และบันทึก baseline tests แยกจาก build เดิม
- Acceptance: staging write ไม่ปรากฏ production; test guard ปฏิเสธ unsafe DB; clean clone ติดตั้งและ migrate ได้

### ระยะ 1: ยอดเงินและข้อมูลสัมพันธ์ (D1,D2,D3,D5,D6,D7)
- Modify: backend/app/reports.py, phase3.py, resources.py, schemas.py, follow_up.py
- Create tests: backend/tests/test_finance_integrity.py, test_schema_boundaries.py, test_resource_lifecycle.py, test_category_concurrency.py
- Test linked/unlinked fuel มากกว่า 10 รายการ, date ranges, amount/date/type edits, pending/completed cycles, FK delete conflict, notes ยาว/null/precision, concurrent settings updates
- แยก dashboard aggregation query จาก recent records; สร้าง finance service กลางแทน logic ซ้ำ
- Acceptance: linked fuel นับครั้งเดียว; cycle summary ยังไม่รวมเชื้อเพลิง; invalid payload เป็น 422 ไม่ 500; conflict เป็น 409; concurrent version เดียวสำเร็จเพียงหนึ่งรายการ

### ระยะ 2: Offline และไฟล์แนบ (O1–O4,A1,A2,D4,U3)
- Modify: lib/services/offline_queue.dart, api_session.dart, farmer_api.dart; screens/schedule_screen.dart, dashboard_screen.dart, field_inspections_screen.dart; widgets/attachment_thumbnail.dart; backend/app/attachments.py
- Create: lib/widgets/task_completion_dialog.dart (ใช้ร่วมหน้าแรก/งาน), lib/screens/sync_queue_screen.dart; test/task_completion_test.dart, test/attachment_retry_test.dart
- คง owner-isolated storage; lock enqueue/flush; durable pending attachment พร้อม parent ID/per-file ID; ลบ successful queue entries แบบไม่ทับงานใหม่
- แสดง saved/queued/partial/failed ต่างกัน; completed task ต้องเปิด retry รูปได้; จำกัด cache/storage และกำหนด logout retention policy
- Tests: enqueue ระหว่าง replay, double sync, offline restart, expired auth, PATCH สำเร็จ/รูปที่สอง fail, cancel ไม่ mutate, reorder parent IDs
- Acceptance: ไม่สูญคิว ไม่สร้าง entity ซ้ำ retry เฉพาะไฟล์ที่ล้มเหลว และรูปทุกใบตรงเจ้าของ/รายการ

### ระยะ 3: Push และ hardening (S1,N1,D9)
- Modify: backend/app/push.py, scheduler.py, notifications.py, schemas.py, models.py
- Create: backend/tests/test_scheduler.py, test_push_delivery.py, migration outbox (ตรวจ next revision ก่อนตั้งชื่อ)
- HTTPS provider allowlist + validate keys + outbound policy, timeout/exception ต่อ subscription, cleanup invalid 404/410
- Transactional outbox pending/claimed/sent/failed, atomic claim, retry/backoff, observability; ไม่อ้าง exactly-once network delivery ให้ deduplicate notification identity ฝั่งแสดงผลด้วย
- Tests: invalid endpoint ถูกปฏิเสธก่อน network, GET ก่อน scheduler, crash/restart, concurrent workers, subscription failure ไม่กระทบผู้ใช้อื่น
- Acceptance: delivery state กู้คืนได้, tenant isolation ผ่าน, scheduler unhealthy มีสัญญาณเตือน

### ระยะ 4: UI/เลย์เอาต์/ภาษาไทย (U1–U6)
- Modify: lib/screens/main_screen.dart, dashboard_screen.dart, work_screen.dart, schedule_screen.dart, activities_screen.dart, cycles_screen.dart, settings_screen.dart
- Create: lib/utils/thai_date.dart, lib/widgets/async_state_view.dart, test/responsive_layout_test.dart, test/thai_date_test.dart
- ใช้ shared invalidation หลัง create/update/delete/sync; loading/error/empty/retry มาตรฐาน; key รูปตาม entity
- รักษาสีและ layout หลัก เพิ่ม responsive tabs/dropdown/buttons และ consistent spacing; ไม่ redesign ทุกหน้าโดยไม่ให้ผู้ใช้ดูตัวอย่างก่อน
- สรุปข้อมูลคงลำดับชื่อแปลง/รอบ → ยอด → กิจกรรม/งาน/ธุรกรรม → กดรายละเอียดและรูป
- พ.ศ. สำหรับ display/picker เท่านั้น API ค.ศ.; semantics มีสถานะข้อความ ไอคอนพร้อม tooltip
- Acceptance matrix: 320/360/390/768/1440 px, text scale 1/1.5/2, ชื่อไทยยาว, ข้อมูลว่าง/error/มาก, keyboard/screen reader; ไม่มี overflow และปุ่มหลักเข้าถึงได้
- เก็บภาพจริง staging แต่ละ breakpoint หลังอนุมัติ ไม่ใช้ข้อมูลผู้ใช้จริงเป็น fixture

### ระยะ 5: Build/Deploy/Recovery (R1,R3–R10,D8)
- Modify: android/app/build.gradle.kts, AndroidManifest.xml, gradle.properties, gradle-wrapper.properties, requirements files, pubspec.yaml, backend/Dockerfile, compose.yaml, deploy configs, .gitignore, README.md
- กำหนด release key ownership/backup ผ่าน secret store; ไม่สร้าง/เปลี่ยน signing key โดยพลการ ตรวจ fingerprint APK เดิมและผลต่อ update ก่อน
- Release ต้อง HTTPS/API URL ชัดเจน; HTTP debug only; pin toolchains/lock/images; ลด lint ignore ทีละ rule
- Portable CI: isolated migrations + backend tests + Flutter analyze/tests + web build; Android release build/sign gate เมื่ออนุมัติ APK
- Artifact build/checksum/cache version จาก pipeline ไม่แก้ generated bootstrap มือทุก deploy; atomic switch และ rollback artifact ก่อนหน้า
- Backup DB + attachment volume + web เป็น recovery set; restore ไป isolated host และตรวจ migration head/รูป/auth/API ก่อน production rollout
- Acceptance: clean clone build ได้; upload 10 MiB ผ่าน proxy; scheduler wired; no secret ใน git/bundle/log; health + public bundle hash ตรง; downgrade ไม่ทำลายข้อมูลโดยไม่มีแผน

## คำสั่งตรวจเมื่อเริ่ม implementation (ยังไม่ได้รันใน audit)
```bash
flutter analyze
flutter test
flutter build web --release --dart-define=FARM_API_BASE_URL=/
```
ใน disposable backend test environment เท่านั้น:
```bash
alembic upgrade head
python3 -m pytest -q
```
ต้องกำหนด DATABASE_URL ผ่าน secret environment ที่ชี้ test DB ก่อน ไม่ใส่ connection string ในเอกสารนี้

## โครงสร้างโค้ดเป้าหมาย
- แยก finance/task completion/attachment delivery เป็น service ไม่กระจาย state machine ตามหน้าจอ
- รวม date formatter, async UI state, completion dialog และ theme tokens ที่ใช้ซ้ำ
- พิจารณาย้าย lib/features/<domain>/ แบบทีละ feature หลัง regression tests พร้อม ไม่ย้ายทั้ง repository ใน commit เดียว
- เพิ่ม pagination/query aggregation เมื่อมี benchmark ข้อมูลจำลอง ไม่เปลี่ยน API เพราะเดาปริมาณข้อมูล

## คำถามที่ต้องตัดสินใจก่อนส่วนที่เกี่ยวข้อง
1. Offline session ต้องใช้งานได้นานเท่าไร และ logout จะเก็บหรือลบ pending files อย่างไร?
2. ลบ inspection/ย้าย cycle ที่มีงานอัตโนมัติแล้ว: ห้ามย้าย, ย้ายตาม หรือยกเลิกงาน? เสนอ block พร้อมอธิบายก่อน เพื่อไม่เปลี่ยนข้อมูลเงียบ ๆ
3. Signing certificate เดิมมีผู้ใช้งาน APK อยู่แล้วหรือไม่? วางแผนอัปเกรดโดยไม่ทำข้อมูลบนอุปกรณ์สูญ
4. Single image plot/activity จะคงนโยบายเดิมหรือเปลี่ยนหลายรูป? ห้ามเพิ่ม unique constraint จนยืนยัน data policy และตรวจ duplicates แบบ read-only

## ลำดับแนะนำและ Definition of Done
เริ่มระยะ 0 → 1 → 2 เพราะเกี่ยวกับความถูกต้อง/ข้อมูลสูญหายก่อนความสวยงาม; ระยะ 3 hardening ก่อนเปิด push เพิ่ม; UI ระยะ 4 ทำเป็นชุดเล็กให้ตรวจภาพ; ระยะ 5 release gate ก่อนแจก/Deploy รุ่นใหม่

งานเสร็จเมื่อ regression tests ครอบคลุม acceptance, review ผ่าน, staging isolated ผ่าน, มี backup/restore evidence และได้รับอนุมัติ Production เท่านั้น การที่ build ผ่านไม่เท่ากับพิสูจน์ UI/ข้อมูลถูกต้องทั้งหมด

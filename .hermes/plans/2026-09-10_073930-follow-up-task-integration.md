# Field Inspection Follow-up Task Integration Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** เมื่อผู้ใช้เปิด “ต้องติดตามผล” ในการตรวจแปลง ให้ระบบสร้างงานติดตามผลในตารางงานอัตโนมัติ งานนั้นปิดได้จากตารางงาน และข้อมูลสถานะ/ผลการติดตามแสดงในรอบผลิตที่เกี่ยวข้อง

**Architecture:** เพิ่มความสัมพันธ์แบบ explicit ระหว่าง `Task` กับ `FieldInspection` โดยใช้ nullable `field_inspection_id` และ unique constraint ต่อ owner/inspection เพื่อให้ retry และการแก้ไขรายการเดิมไม่สร้างงานซ้ำ ใช้สถานะ `Task.status = completed` เป็นสถานะปิดงานจากหน้าตารางงาน และให้ API ตรวจแปลงเป็นจุดควบคุมการสร้าง/อัปเดต/ยกเลิกงานติดตามผลภายใน transaction เดียวกัน ส่วน Cycle Timeline ดึง task ที่ผูกกับรอบผลิตและแสดงรายละเอียดการติดตามผล

**Tech Stack:** FastAPI, SQLAlchemy, Alembic, PostgreSQL, Flutter/Dart, existing Tasks API and Cycle Timeline.

---

## Current context / assumptions

- `FieldInspection` มี `follow_up_required` และ `follow_up_date` แต่ยังไม่มีสถานะปิดงานหรือ foreign key ไปยัง `Task`.
- `Task` ปัจจุบันมี `owner_id`, `cycle_id`, `due_date`, `status`, `description` และรองรับ `pending`, `in_progress`, `completed`.
- Task บังคับมี `cycle_id`; จึงจะสร้างงานอัตโนมัติได้เฉพาะ inspection ที่เลือก cycle แล้ว หากไม่มี cycle ต้องแสดงคำเตือนที่ชัดเจนและไม่สร้าง task.
- หน้าตารางงานมีปุ่ม `สำเร็จ` และเปลี่ยนสถานะเป็น `completed` อยู่แล้ว.
- Cycle Timeline แสดง activities และ tasks ตาม `cycle_id` อยู่แล้ว แต่ยังไม่ระบุว่า task ใดเป็นงานติดตามผล.
- ต้องรักษา owner scoping, ไม่สร้าง task ซ้ำเมื่อ retry/แก้ไข/เปิดรายการเดิมซ้ำ และต้อง backup ก่อน migration/deploy Production.
- จะไม่ลบข้อมูล Production และจะทดสอบกับฐานข้อมูลแยกก่อน migration จริง.

## Proposed data behavior

1. เปิดติดตามผล + มี `followUpDate` + มี `cycleId`:
   - สร้าง inspection และ follow-up task ใน transaction เดียวกัน
   - task name เช่น `ติดตามผลการตรวจแปลง: <ชื่อแปลง>`
   - task due date = `followUpDate`
   - task description มี inspection id/status/คำแนะนำที่จำเป็นโดยไม่ทำให้ข้อมูลซ้ำซ้อน
   - task ผูก `owner_id`, `plot_id` ผ่าน cycle, `cycle_id`, `field_inspection_id`
2. แก้ inspection เดิม:
   - ถ้ายังต้องติดตามผล ให้ update task เดิม (วันครบกำหนด/ชื่อ/description/cycle ตามข้อมูลใหม่)
   - ถ้าปิดการติดตามผล ให้ยกเลิกหรือ mark task เดิมอย่างชัดเจน โดยแนะนำ `completed` ไม่เหมาะกับงานที่ไม่ได้ทำ จึงควรเพิ่มสถานะ `cancelled` หรือใช้ deletion/ยกเลิกแบบ audit ตามข้อสรุปใน implementation review
   - ห้ามสร้าง task ใหม่ถ้ามี task ผูก inspection เดิมอยู่
3. ปิดงานจากตารางงาน:
   - ใช้ปุ่ม `สำเร็จ`/สถานะ `completed` ของ task เดิม
   - inspection ที่ผูก task จะสะท้อน `follow_up_status = completed` ผ่าน API response หรือ derived status
   - เก็บ `follow_up_completed_at` และ `follow_up_completed_by` หากต้องการ audit; แนะนำให้เพิ่มเพื่อให้รายละเอียดรอบผลิตเชื่อถือได้
4. Cycle Timeline:
   - แสดงรายการตรวจแปลงที่มี follow-up และ task ที่ผูกกันในรายการเดียวกันหรือแสดง badge `ติดตามผล`
   - แสดงสถานะ `รอติดตาม`, `กำลังดำเนินการ`, `ติดตามผลเสร็จแล้ว`
   - ปุ่มปิดงานหลักยังอยู่ในหน้าตารางงาน และ Timeline แสดงสถานะล่าสุดแบบ read-only
5. กรณี inspection ไม่มี cycle:
   - inspection ยังคงบันทึกได้ตาม requirement เดิม
   - ไม่สร้าง task อัตโนมัติ เพราะ Task schema ต้องมี cycle
   - UI แจ้งว่า “การติดตามผลอัตโนมัติต้องผูกรอบผลิตก่อน” และไม่ควรทำให้การบันทึก inspection ล้มเหลวโดยไม่มีคำอธิบาย

---

## Step-by-step implementation plan

### Task 1: สรุป state machine และ acceptance tests

**Files:**
- Modify: `backend/tests/test_field_inspections.py`
- Modify: `backend/tests/test_notifications.py` หาก notification behavior เปลี่ยน
- Create/Modify: `.hermes/plans/` เอกสารนี้

**Steps:**
1. เพิ่ม failing API tests สำหรับ create inspection + follow-up task หนึ่งรายการ.
2. เพิ่ม test retry/patch เดิมแล้ว assert task count ยังคงเป็นหนึ่ง.
3. เพิ่ม test update follow-up date แล้ว task เดิมเปลี่ยน due date.
4. เพิ่ม test task completed แล้ว inspection response แสดงสถานะเสร็จ.
5. เพิ่ม test owner A ไม่เห็น/แก้ task ของ owner B.
6. เพิ่ม test inspection ไม่มี cycle ว่าบันทึกได้แต่ไม่สร้าง task และ response อธิบายข้อจำกัดตาม design ที่เลือก.

### Task 2: เพิ่ม schema และ migration สำหรับความสัมพันธ์

**Files:**
- Modify: `backend/app/models.py`
- Modify: `backend/app/schemas.py`
- Create: `backend/migrations/versions/0012_field_inspection_followup_tasks.py`

**Steps:**
1. เพิ่ม `Task.field_inspection_id` nullable FK ไป `field_inspections.id` พร้อม index.
2. เพิ่ม unique constraint ป้องกัน task อัตโนมัติซ้ำต่อ inspection โดยควรเป็น partial unique index ที่ใช้กับ task ที่มี field inspection id.
3. เพิ่มฟิลด์ audit ที่เลือกใช้ เช่น `FieldInspection.follow_up_completed_at` และ `follow_up_completed_by` หรือกำหนด derived status จาก task หากลด schema change ได้.
4. ขยาย `TaskOut` ให้มี `fieldInspectionId`, `isAutomaticFollowUp` หรือข้อมูลที่ UI ต้องใช้.
5. ขยาย `FieldInspectionOut` ให้มี `followUpStatus`, `followUpTaskId`, `followUpCompletedAt` แบบ computed/response fields.
6. กำหนดสถานะ task และกติกา cancelled ให้ชัดเจนก่อน migration; ถ้าเพิ่ม `cancelled` ต้องอัปเดต validator/check constraint/notification query/tests ให้ครบ.
7. ตรวจ downgrade และ migration chain ในฐานข้อมูลทดสอบ.

### Task 3: สร้าง service สำหรับ idempotent follow-up task

**Files:**
- Create: `backend/app/field_inspection_followups.py`
- Modify: `backend/app/field_inspections.py`
- Modify: `backend/app/phase3.py`

**Steps:**
1. สร้างฟังก์ชัน `sync_follow_up_task(db, owner, inspection)` ที่ query ด้วย `owner_id + field_inspection_id`.
2. เมื่อเปิดติดตามผลและมีวัน/รอบผลิต ให้ create หรือ update task เดิม.
3. เมื่อปิดติดตามผล ให้ใช้กติกา cancelled/delete ที่เลือก และไม่สร้าง task ใหม่.
4. ให้ create/patch inspection เรียก service ใน transaction เดียวกันก่อน commit.
5. ป้องกัน race condition ด้วย unique index และจัดการ IntegrityError โดยอ่าน task เดิมกลับมาแทนการสร้างซ้ำ.
6. ถ้า cycle เปลี่ยน ต้องตรวจ owner และ plot-cycle consistency ก่อน update task.
7. ให้ response คำนวณสถานะจาก task ที่ owner เดียวกันเท่านั้น.
8. เพิ่ม tests unit/API สำหรับทุก branch และ retry.

### Task 4: ทำให้ task completion สะท้อนกลับ inspection

**Files:**
- Modify: `backend/app/phase3.py`
- Modify: `backend/app/field_inspections.py`
- Modify: `backend/tests/test_field_inspections.py`

**Steps:**
1. เมื่อ `PATCH /tasks/{id}` เปลี่ยน linked task เป็น `completed` ให้บันทึก audit fields ของ inspection หากเลือกเก็บ audit.
2. ป้องกันการแก้ task ของ owner อื่นและการเปลี่ยน cycle ไปยัง cycle ของ owner อื่น.
3. ให้ task completion ไม่สร้าง task ใหม่และไม่เปลี่ยนข้อมูล inspection หลัก.
4. ทดสอบการปิดจาก endpoint เดิมที่หน้า Schedule ใช้อยู่.
5. ตรวจ notification scheduler ว่างาน completed ไม่ถูกแจ้งเตือนซ้ำ.

### Task 5: ปรับ Flutter models/API และฟอร์มตรวจแปลง

**Files:**
- Modify: `lib/models/api_models.dart`
- Modify: `lib/services/farmer_api.dart`
- Modify: `lib/screens/field_inspections_screen.dart`

**Steps:**
1. เพิ่ม model fields สำหรับ follow-up task id/status/completed time.
2. แยก field ที่เป็น UI-only ออกจาก JSON และส่งวันที่ ISO ค.ศ. ตามที่แก้ 422 ไว้แล้ว.
3. เมื่อเปิดติดตามผลและไม่มี cycle ให้แสดงคำเตือนก่อนบันทึกว่าไม่สามารถสร้างงานอัตโนมัติได้; ให้ผู้ใช้เลือกว่าจะผูก cycle หรือบันทึก inspection โดยไม่มี task ตาม design.
4. ในรายละเอียด inspection แสดงชื่อ task, วันครบกำหนด และสถานะ.
5. เพิ่มปุ่มเปิดหน้าตารางงานหรือ cycle timeline จากรายละเอียดรายการตรวจ.
6. เมื่อกลับจากการปิดงาน ให้ refresh inspection list/detail.
7. เพิ่ม widget tests สำหรับ toggle/date/cycle/ข้อความ validation.

### Task 6: ปรับหน้าตารางงานให้ระบุและปิดงานติดตามผล

**Files:**
- Modify: `lib/models/api_models.dart`
- Modify: `lib/screens/schedule_screen.dart`
- Modify: `lib/screens/dashboard_screen.dart` หาก dashboard แสดง task เดียวกัน

**Steps:**
1. แสดง badge `ติดตามผลการตรวจแปลง` สำหรับ task ที่มี `fieldInspectionId`.
2. ใช้ปุ่ม `สำเร็จ` เดิมเพื่อเปลี่ยนสถานะเป็น `completed`.
3. หลังสำเร็จ refresh task และแสดง SnackBar ว่า `ปิดงานติดตามผลแล้ว`.
4. ป้องกันการซ่อนข้อมูลที่จำเป็นใน completed view; หน้าแรกยังซ่อน completed ตาม requirement เดิม.
5. เพิ่ม widget test ว่าปุ่มปิดเรียก update task ด้วยสถานะ `completed`.

### Task 7: แสดงข้อมูลในรอบผลิต

**Files:**
- Modify: `lib/screens/cycles_screen.dart`
- Modify: `backend/app/phase3.py` หรือ endpoint cycle detail หาก response ต้องเพิ่ม summary
- Add/Modify: backend cycle tests and Flutter tests

**Steps:**
1. ให้ Cycle Timeline แสดง task linked inspection พร้อม badge และสถานะ.
2. แสดงวันที่ตรวจแปลง, วันติดตามผล และสถานะปิดงานในรายการ timeline.
3. ถ้าต้องการรายละเอียด inspection เพิ่ม ให้เพิ่ม endpoint/query ที่ owner-scoped; ห้ามให้ client query id ข้าม owner.
4. ให้ timeline refresh หลังปิด task หรือกลับจากรายละเอียด.
5. เพิ่ม test cycle ที่มี inspection follow-up pending/completed และตรวจลำดับตามวันที่.

### Task 8: ทดสอบฐานข้อมูลแยก, backup และ deploy Production

**Files:**
- Modify: deployment files only if required: `deploy/production/compose.yaml`, `deploy/production/nginx.conf`
- No production data fixture files

**Steps:**
1. ใช้ PostgreSQL test database แยกจาก Production และ run `alembic upgrade head`.
2. Run backend tests ทั้งชุด; expected existing suite plus new follow-up tests pass.
3. Run `dart format`, `flutter analyze`, `flutter test`, and `flutter build web --release --dart-define=FARM_API_BASE_URL=/`.
4. สร้าง backup Production ก่อน migration/deploy และเก็บ path/เวลาไว้ใน deploy record โดยไม่เปิดเผย secrets.
5. Apply migration และ restart เฉพาะ service ที่เกี่ยวข้อง.
6. Verify migration head, API health/database health, scheduler health, public Web HTTP 200.
7. Verify same-origin bundle hash และ cache-busting.
8. ทดสอบแบบ authenticated ด้วยบัญชีทดสอบที่ไม่ใช่ข้อมูลเกษตรกรจริง:
   - สร้าง inspection ที่เปิดติดตามผล
   - อ่าน tasks แล้วพบ task เดียว
   - patch/retry แล้ว count ยังเป็นหนึ่ง
   - ปิดจากตารางงาน
   - อ่าน inspection และ cycle timeline พบสถานะ `ติดตามผลเสร็จแล้ว`
9. อ่านกลับข้อมูลเป้าหมายหลังทุก state-changing request เพื่อยืนยันผลจริง.

---

## Acceptance criteria

- เปิด `ต้องติดตามผล` และเลือกวันที่/รอบผลิตแล้ว บันทึก inspection สำเร็จและสร้าง task อัตโนมัติหนึ่งรายการ.
- Retry หรือแก้ไขรายการเดิมไม่สร้าง task ซ้ำ.
- วันติดตามผลที่แก้ไขอัปเดต task เดิม.
- งานติดตามผลปิดได้จากหน้าตารางงานด้วยสถานะ `completed`.
- หลังปิดงาน สถานะในรายการตรวจแปลงและรอบผลิตแสดงว่าเสร็จแล้ว.
- Cycle Timeline แสดงข้อมูลตรวจแปลงและงานติดตามผลใน cycle ที่ถูกต้อง.
- owner อื่นไม่สามารถเห็นหรือแก้ข้อมูลได้.
- notification ไม่สร้าง/ส่งซ้ำหลังงาน completed.
- กรณีไม่มี cycle มีพฤติกรรมที่อธิบายชัดเจนและไม่ทำให้เกิด task orphan.
- Backend tests, Flutter analyze/tests/build, migration, health checks และ Public Web ผ่านจริงก่อนรายงานเสร็จ.

## Risks, tradeoffs, and open questions

- **ไม่มี cycle:** Task schema บังคับ cycle; ต้องยืนยันว่าจะบันทึก inspection ต่อโดยไม่มี auto task หรือบังคับเลือก cycle เฉพาะเมื่อเปิดติดตามผล. ข้อเสนอในแผนนี้คือบันทึกได้แต่แจ้งว่า auto task ไม่ถูกสร้าง.
- **ยกเลิก follow-up:** ควรเพิ่ม `cancelled` เพื่อรักษาประวัติและแยกจาก `completed`; หากเพิ่มสถานะจะกระทบ constraints, UI, notification และ tests.
- **Audit ผู้ปิดงาน:** การเก็บ `completed_at/by` ช่วยให้สถานะใน cycle เชื่อถือได้ แต่เพิ่ม migration และข้อมูล response.
- **Atomicity:** การสร้าง inspection และ task พร้อมกันลด orphan แต่ attachment upload ยังเกิดหลัง inspection ตาม design เดิม; ต้องไม่ให้ upload retry สร้าง task ซ้ำ.
- **Production safety:** ห้าม migrate/deploy จนกว่าจะทดสอบ DB แยกและ backup สำเร็จ.

# ระบบบันทึกการตรวจแปลง Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** เพิ่มระบบบันทึกการตรวจแปลงที่ผูกกับแปลงเกษตรและรอบผลิต เก็บผลตรวจ อาการผิดปกติ รูปภาพ และงานติดตาม โดยจำกัดข้อมูลตามเจ้าของบัญชี

**Architecture:** เพิ่ม resource ใหม่ชื่อ `field_inspections` ใน Backend โดยใช้ owner scoping แบบเดียวกับ plots, activities และ tasks ส่วน Flutter เพิ่ม model/API client, หน้ารายการตรวจแปลง, Popup Dialog สำหรับบันทึก และทางลัดจากปุ่ม `+` บน NavigationBar ข้อมูลรูปภาพใช้ attachment system เดิมหลังสร้างรายการตรวจสำเร็จ

**Tech Stack:** FastAPI, SQLAlchemy, Alembic, PostgreSQL, Flutter Material 3, Provider, API เดิมของ farmer-main

---

## 1. ขอบเขตฟีเจอร์ที่เสนอ

### ข้อมูลหลักของการตรวจแปลง

- แปลงเกษตร — จำเป็นต้องเลือก
- รอบผลิต — เลือกได้ ถ้าแปลงมีหลายรอบผลิตควรกรองเฉพาะรอบที่อยู่ในแปลงนั้น
- วันที่ตรวจ — ค่าเริ่มต้นเป็นวันนี้
- ผู้ตรวจ — ค่าเริ่มต้นเป็นชื่อผู้ใช้ ถ้าไม่มีชื่อใช้ email เดิม และไม่เปิดให้กรอกเจ้าของคนอื่น
- สภาพรวม — `ปกติ`, `เฝ้าระวัง`, `พบปัญหา`
- หมายเหตุ/รายละเอียด — ข้อความหลายบรรทัด

### Checklist ที่ควรมีใน MVP

เก็บเป็นข้อมูลที่แก้ไขได้ในรายการตรวจ ไม่ผูกกับข้อความรวม เพื่อให้แสดงผลและกรองภายหลังได้:

- สุขภาพต้นพืช
- แมลง/ศัตรูพืช
- โรคพืช
- วัชพืช
- ความชื้น/การให้น้ำ
- สภาพดิน
- ความเสียหายจากสภาพอากาศ

ค่าของแต่ละหัวข้อ: `ปกติ`, `เฝ้าระวัง`, `พบปัญหา`, หรือ `ไม่ได้ตรวจ`

### การติดตามผล

- ข้อเสนอแนะ/วิธีแก้ไข
- ต้องติดตามต่อหรือไม่
- วันนัดติดตาม (ถ้ามี)
- ปุ่มสร้างตารางงานจากผลตรวจ — ทำเป็นระยะถัดไปหลัง MVP เพื่อไม่สร้างงานซ้ำโดยไม่ตั้งใจ

### รูปภาพหลายรูป

- หลังบันทึกรายการตรวจแล้ว ให้ใช้ attachment API เดิมแนบรูปได้หลายรูปต่อหนึ่งรายการตรวจ
- เปิดให้เลือกและอัปโหลดหลายไฟล์จาก Gallery ในการกดครั้งเดียว หรือกดเพิ่มซ้ำได้
- อัปโหลดทีละไฟล์พร้อมแสดงสถานะกำลังอัปโหลด/สำเร็จ/ล้มเหลวแยกรูป
- หากบางรูปอัปโหลดล้มเหลว ต้องไม่ทำให้รูปที่สำเร็จแล้วหาย และสามารถลองเฉพาะรูปที่ล้มเหลวใหม่ได้
- แสดงรูปเป็น grid thumbnail ในรายละเอียด
- กดดูรูปเต็ม, ลบรูปที่แนบผิด และยืนยันก่อนลบ
- ไม่เก็บไฟล์รูปในฐานข้อมูลโดยตรง
- กำหนด validation เดิมของระบบต่อไฟล์ เช่น ชนิดไฟล์ JPEG/PNG/WebP และขนาดสูงสุด 10 MiB ต่อไฟล์
- ก่อน Deploy ต้องทดสอบกรณี 1 รูป, หลายรูป, รูปเกินขนาด, ไฟล์ชนิดไม่รองรับ และการอัปโหลดบางรูปไม่สำเร็จ

---

## 2. โครงสร้างข้อมูล Backend

### ตาราง `field_inspections`

เสนอคอลัมน์:

- `id UUID` primary key
- `owner_id UUID` foreign key ไป `users.id`, index
- `plot_id UUID` foreign key ไป `plots.id`, index, `ON DELETE RESTRICT`
- `cycle_id UUID NULL` foreign key ไป `production_cycles.id`, index, `ON DELETE RESTRICT`
- `inspection_date DATE` not null
- `overall_status VARCHAR(20)` not null, ตรวจค่า `normal|watch|problem`
- `checklist JSONB` not null, default เป็น object ว่าง
- `notes TEXT NULL`
- `recommendation TEXT NULL`
- `follow_up_required BOOLEAN` not null, default false
- `follow_up_date DATE NULL`
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`

เพิ่ม constraint สำคัญ:

- `follow_up_date` ต้องมีค่าเมื่อ `follow_up_required=true` หรืออนุญาตให้ nullable ใน MVP พร้อม validation ที่ API
- ตรวจว่า `cycle_id` ที่ส่งมาต้องเป็นของ owner เดียวกันและอยู่ใน `plot_id` เดียวกัน
- ทุก query ต้อง filter `owner_id` จาก session ห้ามเชื่อ owner id จาก request

### API ที่เสนอ

- `GET /api/v1/field-inspections`
  - query: `plotId`, `cycleId`, `from`, `to`, `status`
  - เรียง `inspection_date DESC, created_at DESC`
- `GET /api/v1/field-inspections/{id}`
- `POST /api/v1/field-inspections`
- `PATCH /api/v1/field-inspections/{id}`
- `DELETE /api/v1/field-inspections/{id}`

Response ควรมีชื่อแปลงและชื่อรอบผลิตสำหรับแสดงผล โดยยังคงส่ง `plotId`/`cycleId` ตามรูปแบบ API เดิม

ใช้ idempotency key สำหรับ `POST` ตาม pattern ของ API client เดิม เพื่อป้องกันการกดบันทึกซ้ำ

---

## 3. แผนหน้าจอ Flutter

### หน้ารายการตรวจแปลง

ไฟล์ที่เสนอ: `lib/screens/field_inspections_screen.dart`

ประกอบด้วย:

- รายการการตรวจล่าสุด
- filter แปลง, รอบผลิต, สถานะ, ช่วงวันที่
- card แสดงวันที่, ชื่อแปลง, รอบผลิต, badge สภาพรวม
- กด card เพื่อดูรายละเอียด
- แก้ไข/ลบจาก Popup menu
- ปุ่มเพิ่มเดิมยังคงมีได้ แต่ทางเข้าหลักคือปุ่ม `+` กลาง NavigationBar

### Popup Dialog บันทึก

ไฟล์เดียวกันหรือแยกเป็น `lib/widgets/field_inspection_dialog.dart`

ลำดับช่อง:

1. แปลง
2. รอบผลิต
3. วันที่ตรวจ
4. สภาพรวม
5. Checklist แบบ Dropdown/Segmented control
6. หมายเหตุ
7. ข้อเสนอแนะ
8. ต้องติดตามต่อหรือไม่
9. วันนัดติดตามเมื่อเปิดใช้งาน
10. ปุ่มบันทึก/ยกเลิก

ใช้ระยะห่างระหว่างช่องอย่างน้อย `12px` ตามรูปแบบ Popup Dialog ล่าสุดของระบบ

### หน้ารายละเอียด

แสดง:

- ข้อมูลแปลงและรอบผลิต
- วันที่ตรวจและผู้บันทึก
- สภาพรวมแบบสี/จุดสถานะ
- checklist ทั้งหมด
- หมายเหตุและข้อเสนอแนะ
- รายการติดตาม
- รูปภาพที่แนบ
- ปุ่มแก้ไข, ลบ และแนบรูป

### ปุ่ม `+` กลาง NavigationBar

เพิ่มตัวเลือก:

- เพิ่มรายการการเงิน
- เติมเชื้อเพลิง
- เพิ่มกิจกรรม
- เพิ่มตารางงาน
- **เพิ่มการตรวจแปลง**

ฟอร์มเปิดจากปุ่ม `+` ต้องใช้ dialog เดียวกับหน้ารายการตรวจแปลง ไม่ทำสำเนา logic คนละชุด

---

## 4. ไฟล์ที่คาดว่าจะสร้าง/แก้ไข

### Backend

- Create: `backend/migrations/versions/0011_field_inspections.py`
- Modify: `backend/app/models.py`
- Create: `backend/app/field_inspections.py` หรือรวมใน `backend/app/phase3.py` ตาม pattern ที่เหมาะสม
- Modify: `backend/app/main.py` เพื่อ include router/health migration head
- Create/Modify: `backend/tests/test_field_inspections.py`

### Flutter

- Create: `lib/screens/field_inspections_screen.dart`
- Modify: `lib/models/api_models.dart`
- Modify: `lib/services/farmer_api.dart`
- Modify: `lib/screens/main_screen.dart`
- Modify: `lib/screens/work_screen.dart` ถ้าต้องเพิ่มเมนูย่อย `การตรวจแปลง`
- Modify: `lib/screens/dashboard_screen.dart` ถ้าต้องแสดงรายการตรวจล่าสุดบนหน้าแรก
- Modify: `test/api_models_test.dart`
- Create/Modify: `test/field_inspections_test.dart` และ `test/widget_test.dart`

---

## 5. ลำดับการทำงานแบบ TDD

### Task 1: กำหนด schema และ migration

- เขียน backend test ตรวจว่าข้อมูล inspection มี owner, plot, status และวันตรวจ
- รัน test ให้ fail
- เพิ่ม SQLAlchemy model และ Alembic migration
- ตรวจ migration upgrade/downgrade บนฐานข้อมูลทดสอบแยก Production

### Task 2: เพิ่ม API list/detail/create

- เขียน test สำหรับ owner scoping, validation และ cycle/plot mismatch
- เขียน test ว่า owner A อ่าน/แก้/ลบข้อมูล owner B ไม่ได้
- เพิ่ม router และ Pydantic schemas
- ทดสอบ idempotency ของ POST

### Task 3: เพิ่ม API update/delete และ attachment relation

- เขียน test update/delete ของเจ้าของเดียวกัน
- ตรวจว่า attachment ใช้ `parentType=field_inspection` และ parent id ที่ถูกต้อง
- รัน backend test ทั้งชุด

### Task 4: เพิ่ม Flutter model และ API client

- เพิ่ม `FieldInspection` และ checklist/status parsing
- เพิ่ม `fieldInspections`, `createFieldInspection`, `updateFieldInspection`, `deleteFieldInspection`
- เพิ่ม model tests สำหรับ camelCase response และ nullable fields

### Task 5: สร้าง Dialog บันทึก

- เขียน widget test ตรวจช่องจำเป็นและ validation
- เพิ่ม dependent dropdown แปลง → รอบผลิต
- เพิ่ม Date Picker ภาษาไทยและ พ.ศ. ตามระบบปัจจุบัน
- เพิ่ม checklist และ follow-up fields
- เพิ่ม spacing ระหว่างช่องอย่างน้อย 12px

### Task 6: สร้างหน้ารายการและรายละเอียด

- เพิ่มการแนบรูปหลายรูปแบบเลือกหลายไฟล์
- แสดง progress ต่อไฟล์, retry เฉพาะไฟล์ที่ล้มเหลว และลบรูปที่แนบแล้ว
- เพิ่ม list/filter/detail/edit/delete
- เพิ่ม loading, empty, error และ retry states
- เพิ่มการแสดงรูปผ่าน attachment service เดิม

### Task 7: เชื่อมปุ่ม `+` และเมนูงาน

- เพิ่ม `เพิ่มการตรวจแปลง` ใน bottom sheet ของ `main_screen.dart`
- พิจารณาเพิ่มรายการ `การตรวจแปลง` ใน `work_screen.dart` ตามการใช้งานจริง
- หลังบันทึกสำเร็จให้กลับมาหน้าเดิมและ refresh รายการ

### Task 8: ตรวจสอบและ Deploy

- สร้าง PostgreSQL test database แยก
- รัน backend tests, Flutter analyze, Flutter tests และ web build
- Backup Production ก่อน migration
- Apply migration `0011_field_inspections`
- Deploy API และ Web
- ตรวจ health, migration head, owner scoping และ Public Web
- ตรวจ cache headers/version ของ Flutter bundle

---

## 6. Acceptance Criteria

- ผู้ใช้สร้างบันทึกตรวจแปลงได้โดยเลือกแปลงและวันที่
- รอบผลิตที่เลือกต้องสัมพันธ์กับแปลงที่เลือก
- เลือกผลตรวจรวมและผล checklist ได้
- แก้ไข/ลบได้เฉพาะข้อมูลของเจ้าของบัญชี
- รายการตรวจของเจ้าของอื่นไม่ปรากฏแม้รู้ id
- กดปุ่ม `+` แล้วมี `เพิ่มการตรวจแปลง`
- รูปภาพแนบหลังบันทึกและแสดงในรายละเอียดได้
- ข้อมูลสร้างซ้ำจากการ retry เดิมไม่เกิดรายการซ้ำ
- Date Picker แสดงภาษาไทยและ พ.ศ.
- Popup มีระยะห่างระหว่างช่องสม่ำเสมอ
- Backend tests ผ่านทั้งหมด, Flutter tests ผ่านทั้งหมด, analyze/build ผ่าน
- Production health เป็น `status=ok, database=ok`

---

## 7. ความเสี่ยงและการตัดสินใจที่ต้องยืนยันก่อนเริ่มพัฒนา

1. **Checklist แบบตายตัวหรือปรับแต่งได้** — แนะนำเริ่มแบบตายตัวใน MVP เพื่อให้ใช้งานเร็วและลด schema ซับซ้อน
2. **การตรวจหลายแปลงในครั้งเดียว** — แนะนำหนึ่งรายการต่อหนึ่งแปลง เพื่อให้ติดตามประวัติและรูปภาพชัดเจน
3. **การสร้างตารางงานอัตโนมัติจากผลตรวจ** — แนะนำยังไม่ทำอัตโนมัติใน MVP ให้ผู้ใช้กดสร้างเองในระยะถัดไป เพื่อป้องกันงานซ้ำ
4. **ตำแหน่งเมนู** — แนะนำให้เข้าผ่านปุ่ม `+` ก่อน และค่อยเพิ่มเมนูย่อยในหน้า “งาน” หากต้องดูประวัติเป็นประจำ
5. **สถานะการตรวจ** — แนะนำใช้ 3 ระดับ `ปกติ/เฝ้าระวัง/พบปัญหา` ให้ตรงกับการใช้งานภาคสนามและสีสถานะที่มีอยู่
6. **ผู้ตรวจหลายคน** — ใน MVP ใช้ผู้ใช้ที่ Login เป็นผู้บันทึก ไม่เพิ่มตารางบุคลากรใหม่

**สถานะ:** แผนพร้อมสำหรับการทบทวน ยังไม่มีการแก้โค้ดหรือ Deploy

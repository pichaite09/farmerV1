# Production Cycle Summary Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** เพิ่มเมนู “สรุป” ในหน้าตารางงาน เพื่อดูสิ่งที่ดำเนินการแล้วและยอดรายรับ รายจ่าย กำไร/ขาดทุน แยกตามแต่ละรอบการผลิต

**Architecture:** เพิ่ม endpoint รายงานแบบ owner-scoped ที่รวมข้อมูลจาก production cycles, activities, tasks และ transactions โดยให้รอบการผลิตเป็นศูนย์กลาง จากนั้นเพิ่ม typed API model และแท็บ “สรุป” ใน `ScheduleScreen` ใช้ข้อมูลจาก Backend เดียว ไม่คำนวณยอดจากข้อมูลที่โหลดมาไม่ครบใน Client

**Tech Stack:** FastAPI + SQLAlchemy + PostgreSQL, Flutter/Dart, existing authenticated API session, isolated PostgreSQL tests

**Confirmed scope:** ไม่รวม FuelRecord/ค่าเชื้อเพลิงในสรุปรอบการผลิต และแสดงแต่ละรอบผลิตเป็นการ์ด/ส่วนสรุปแยกกัน ไม่รวมยอดข้ามรอบ

---

## ขอบเขตและพฤติกรรมที่เสนอ

- เมนูใหม่ในหน้า **งาน**: `รายการ` และ `สรุป`
- สรุปแยกเป็นการ์ดของแต่ละรอบการผลิต โดยแสดง:
  - ชื่อรอบการผลิตและชื่อแปลง
  - ช่วงวันที่/สถานะรอบการผลิต
  - จำนวนกิจกรรมที่บันทึก
  - จำนวนงานทั้งหมด / งานที่เสร็จแล้ว / งานคงค้าง
  - รายรับรวม
  - รายจ่ายรวม
  - กำไร/ขาดทุนสุทธิ = รายรับ - รายจ่าย
  - รายการกิจกรรมและงานที่ดำเนินการแล้ว เรียงตามวันที่จริง
  - รายการรายรับรายจ่ายของรอบนั้น
- จำกัดข้อมูลด้วยบัญชีผู้ใช้และ `owner_id` ทุก query
- รอบที่ยังไม่มีข้อมูลจะแสดงยอดเป็นศูนย์และ empty state ที่ชัดเจน
- งานหรือกิจกรรมที่ไม่มีรอบการผลิตไม่ถูกนำไปปนกับการ์ดรอบใด ให้แสดงกลุ่ม `ไม่ผูกรอบการผลิต` แยกเฉพาะถ้าจำเป็น
- ใช้ข้อมูลธุรกรรมที่มี `cycle_id` เป็นรายรับ/รายจ่ายของรอบนั้น
- ยังไม่รวม `FuelRecord`/ค่าเชื้อเพลิงในสรุปรอบการผลิต เพราะยังไม่มีการผูกรอบผลิต
- ธุรกรรมที่ไม่มี `cycle_id` ไม่ถูกนำไปใส่ในสรุปรอบใด

## Task 1: กำหนด API contract และเขียน Backend contract tests

**Files:**
- Modify: `backend/tests/test_reports.py` หรือไฟล์ test รายงานที่มีอยู่
- Modify: `backend/app/reports.py`
- Modify: `backend/app/main.py` เฉพาะการ mount route หากจำเป็น

**Proposed endpoint:**
```text
GET /api/v1/reports/production-cycles/summary?from=YYYY-MM-DD&to=YYYY-MM-DD
```

**Response shape:**
```json
{
  "cycles": [
    {
      "cycleId": "...",
      "cycleName": "รอบนาปี 2569",
      "plotName": "แปลง A",
      "status": "active",
      "startDate": "2026-09-01",
      "endDate": null,
      "activityCount": 2,
      "taskCount": 3,
      "completedTaskCount": 1,
      "income": 10000,
      "expense": 3500,
      "profit": 6500,
      "activities": [],
      "tasks": [],
      "transactions": []
    }
  ],
  "unassigned": {
    "income": 0,
    "expense": 0,
    "profit": 0,
    "fuelExpense": 0
  }
}
```

**Tests:**
- owner A เห็นเฉพาะรอบ/กิจกรรม/งาน/ธุรกรรมของ A
- owner B ไม่เห็นข้อมูลของ A แม้รู้ UUID
- รายรับ/รายจ่ายกรองด้วยช่วงวันที่แบบ inclusive
- รายการกิจกรรม งาน และธุรกรรมอยู่ในรอบที่ถูกต้อง
- งาน completed ถูกนับแยกจากงานคงค้าง
- รอบไม่มีข้อมูลยังมี summary เป็นศูนย์
- ธุรกรรมไม่มี `cycle_id` ไม่ถูกนับในรอบใด
- fuel ถูกสรุปใน `unassigned.fuelExpense` เท่านั้น
- `from > to` ตอบ 422

## Task 2: เพิ่ม typed client models/API

**Files:**
- Modify: `lib/models/api_models.dart`
- Modify: `lib/services/farmer_api.dart`
- Modify: `test/api_models_test.dart`

เพิ่ม model เช่น `ProductionCycleSummary`, `CycleSummaryActivity`, `CycleSummaryTask`, `CycleSummaryTransaction` และเมธอด:
```dart
Future<Map<String, dynamic>> productionCycleSummaries({
  DateTime? from,
  DateTime? to,
})
```

ต้องรักษา wire format camelCase และแปลงวันที่เป็น ISO ก่อนส่ง API รวมถึงแสดง FastAPI validation error ตาม helper เดิม

## Task 3: เพิ่มแท็บ “สรุป” ในหน้า งาน

**Files:**
- Modify: `lib/screens/schedule_screen.dart`
- Add/modify: `test/widget_test.dart` หรือ test หน้าตารางงานที่เหมาะสม

UI:
- TabBar: `รายการ`, `สรุป`
- รายการเดิมและปุ่มเพิ่มงานต้องไม่เปลี่ยนพฤติกรรม
- แท็บสรุปมีตัวกรองช่วงวันที่ที่ใช้ Thai/Buddhist display แต่ส่ง Gregorian ISO
- การ์ดแต่ละรอบมี summary totals ชัดเจนด้วยสีรายรับ/รายจ่าย/กำไร
- ขยายดูรายละเอียดกิจกรรม งาน และธุรกรรมได้
- งาน completed แสดงเป็นดำเนินการแล้ว ไม่แสดงปุ่มปิดงานซ้ำ
- แสดง loading, error, empty state และ retry
- ใช้ layout mobile-first ไม่มี fixed width ที่ทำให้การ์ดล้นจอ

## Task 4: เพิ่ม integration และ regression tests

**Files:**
- Modify: `backend/tests/test_reports.py`
- Modify: `test/api_models_test.dart`
- Modify: `test/widget_test.dart`

รันตามลำดับ:
```bash
python3 -m compileall -q backend/app backend/migrations backend/tests
# Backend ต้องรันกับ isolated PostgreSQL ที่ไม่ใช่ Production
sh /root/farmer-main/.hermes/run-isolated-followup.sh
flutter analyze
flutter test
flutter build web --release --dart-define=FARM_API_BASE_URL=/
```

## Task 5: Production verification/deploy (หลังได้รับอนุมัติ)

1. ตรวจ source และ `docker compose config --quiet`
2. สร้าง PostgreSQL custom-format backup ก่อนเปลี่ยน Backend/schema
3. ถ้าไม่เพิ่ม FuelRecord cycle link ไม่ต้องมี migration; ถ้าเพิ่มต้องสร้าง migration แยกและทดสอบ rollback/owner scoping
4. Deploy Backend และ Web ตาม stack ที่ใช้งานจริง
5. ตรวจ API health, migration head (ถ้ามี), container health และ Public Web HTTP 200
6. เปรียบเทียบ SHA-256 bundle local กับ Public Web
7. ทดสอบ authenticated summary ด้วยบัญชีทดสอบใน isolated DB และตรวจว่า unauthenticated API ได้ 401
8. เก็บ backup path และรายงานข้อจำกัดเรื่องน้ำมันที่ไม่ผูกรอบผลิต

## ไฟล์ที่คาดว่าจะเปลี่ยน

- `backend/app/reports.py`
- `backend/tests/test_reports.py` หรือ test รายงานปัจจุบัน
- `lib/models/api_models.dart`
- `lib/services/farmer_api.dart`
- `lib/screens/schedule_screen.dart`
- `test/api_models_test.dart`
- `test/widget_test.dart`
- อาจมี migration ใหม่ เฉพาะกรณีผู้ใช้อนุมัติให้ผูก FuelRecord กับ production cycle

## ข้อสรุปที่ยืนยันแล้ว

1. ไม่รวมค่าเชื้อเพลิงในสรุปรอบการผลิต
2. แยกสรุปแต่ละรอบผลิต ไม่รวมยอดข้ามรอบ
3. รวมทั้งรอบที่กำลังดำเนินการและรอบที่ปิดแล้ว แต่แสดงเป็นคนละส่วน
4. ช่วงวันที่เริ่มต้นใช้ช่วงวันที่ของแต่ละรอบการผลิตทั้งหมด ไม่ตัดเฉพาะเดือนปัจจุบัน

ยังไม่มีการแก้โค้ดหรือ Deploy จากแผนนี้

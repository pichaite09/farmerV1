# Farmer-main capability parity — Phase 5

Baseline UI = zip ต้นฉบับ ไม่ใช่ farm-data-system/mobile. ระยะ 1–5 มี backend/API และ active Flutter UI ตามรายการที่ตรวจแล้ว; attachments และ offline ผ่านตามข้อจำกัดที่ระบุใน phase5-report. ภาพ upload เป็น online-only และ notification/background sync ยัง partial. การมี source Firebase หรือ prototype ไม่ถือว่าผ่าน parity. คอลัมน์ Tests เป็น acceptance ที่ต้องทำ ไม่ใช่ผลทดสอบเดิมที่ยังไม่ได้รัน.

| UI / source under lib | Controls / behavior ที่ต้องรักษา | API | Tests |
|---|---|---|---|
| main.dart, screens/main_screen.dart | ชื่อเกษตรกร, หน้าแรก/งาน/การเงิน/เชื้อเพลิง/ตั้งค่า, logout confirm | auth/me/logout | branding/menu/session ไม่มีสมุดไร่นาแทน |
| screens/auth_screen.dart | email/password, login/register toggle, validation/loading/error | auth/login/register | login real account, expiry, restore, invalid credentials |
| screens/dashboard_screen.dart | responsive mobile/wide, day/month/year filter, income/expense/profit, expense chart, recent activities/fuel, fuel by vehicle | dashboard | populated/null-safe/period/tenancy |
| screens/work_screen.dart | tabs แปลง/รอบผลิต/กิจกรรม/ตารางงาน | child endpoints | ทุก tab ไปหน้าถูกต้อง |
| screens/plots_screen.dart | list, total area/count, add/edit prefills, slide delete confirmation, camera/gallery, photo zoom | plots,attachments | CRUD/image failure/parent409 |
| screens/cycles_screen.dart | list/start-date sort, name/crop/plot/method/date, edit/delete, active/completed toggle, crop age | cycles,plots,categories | joined name/date/FK/closed cycle edits |
| screens/activities_screen.dart | latest sort, cycle/type/date/description/photo, add/edit/delete, harvest marks completed | activities,cycles,attachments | atomic harvest + owner checks |
| screens/schedule_screen.dart | calendar/date select, tasks, name/cycle/dueDate/description/status, add/edit/delete/status control, local reminder cancel/reschedule | tasks,cycles | Thai status mapping, permission, no fake web push |
| screens/finance_screen.dart | tabs รายการ/สรุปผล | transactions,reports/finance | correct navigation |
| screens/transactions_screen.dart | income/expense, category/item/amount บาท/date, general or cycle, conditional vehicle/fuel type, edit/delete | transactions,vehicles,cycles,categories | general→null; linked fuel atomic/retry/edit/delete |
| screens/summary_screen.dart | financial summaries/charts and date-period filters | reports/finance | all rows aggregate/owner/period |
| screens/fuel_management_screen.dart | tabs ยานพาหนะ/บันทึก/สรุป | child endpoints | correct navigation |
| screens/fuel_tabs/vehicles_list_tab.dart | name/category/licensePlate/color/details, add/edit/delete | vehicles | foreign owner, delete fuel conflict |
| screens/fuel_tabs/fuel_records_list_tab.dart | vehicle/fuelType/amount บาท/date/details, add/edit/delete | fuel-records,vehicles | ไม่ตีความ amount เป็นลิตร, linked vs standalone |
| screens/fuel_tabs/fuel_summary_tab.dart | period filter/vehicle summaries | reports/fuel | sums ไม่ duplicate financial expense |
| screens/settings_screen.dart, providers/category_provider.dart | list/add/delete ของ activityCategories/expenseCategories/incomeCategories/soilTypes/plantingTypes | settings/categories | defaults, owner isolation, concurrency, history preserved |
| services/notification_service.dart | init/permission/schedule/cancel platform-specific | tasks source only | no web unsupported plugin; stable IDs |
| widgets/confirm_dialog.dart, category_card.dart | confirmations/cards retained | applicable resource | cancel no mutation, failed save keeps form |

## Coverage inventory and exclusions
- source-inventory.json เก็บ Dart file inventory พร้อม hashes/collections จาก baseline ต้นฉบับ.
- ll1.dart และ firebase_options.dart ถูกลบจาก active project; ไม่ลบ Firebase remote project และไม่มีการนำข้อมูลเดิมมาใช้.
- ปรับปรุงใหม่: typed JSON, auth errors, server aggregates, offline ownership, image validation, transaction/fuel linkage, editable crop text รองรับข้าว/มันสำปะหลัง.
- ไม่รวม Firebase import, สมุดไร่นา hierarchy, push server, weather หรือการสร้าง sample business records.

## Discovery defects to fix (not yet fixed)
1. Prototype main.dart ใช้ ApiHomeScreen แบบย่อและไม่ใช่ navigation เดิม.
2. Prototype dashboard contract เคย income/expense ต่างจาก API สมุดไร่นา; ห้าม reuse ผิด product.
3. Finance edit สร้าง fuel doc ใหม่ทุกครั้งโดยไม่มี linkage.
4. general cycle ไม่ใช่ UUID; ต้อง normalize null ก่อนส่ง API.
5. Task label ภาษาไทยต้อง map enum ไม่บังคับ backend schema ของสมุดไร่นา.
6. createdAt จาก client และ Timestamp fallback now ต้องเปลี่ยนเป็น server timestamp/strict date.
7. Image upload failure ต้นฉบับคืน null และอาจทับรูปเก่า ต้องเก็บค่าเดิมและแสดง error.
8. Task notification platform support ต้องแยก mobile/Web; compile ผ่านไม่แปลว่าส่งแจ้งเตือนจริง.

- ระยะ 3 backend implement และ deploy/verify แล้ว: ดู `phase3-report.md`; rows ที่เกี่ยวข้องเลื่อนเป็น **partial** จนกว่าจะเชื่อม Flutter/UI

## Phase 1 update
Authentication backend และ PostgreSQL migrations deploy/test แล้ว: ดู `phase1-report.md` (33 tests ผ่านกับ PostgreSQL จริง). แถว main/auth เป็น **partial**: API verified แต่ Flutter/UI integration ยังไม่ทำ; แถวอื่นยัง **backend-blocked**. ข้อความ phase 0 ด้านบนเก็บเป็น baseline ณ เวลานั้น ไม่ใช่สถานะ API ปัจจุบัน.

## Gate phase 0
Source snapshot + contract + parity docs เสร็จ; gate ของ implementation เป็นระยะถัดไป. ไม่มีฟังก์ชันใหม่ใดถูกประกาศว่าใช้งานจริงแล้ว.

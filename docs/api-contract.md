# Farmer-main API contract — Phase 0 baseline v1

สถานะ: ตรึงขอบเขตสำหรับ implementation; ยังไม่มี endpoint ใหม่ที่ผ่าน runtime verification.
แหล่งอ้างอิงต้นฉบับ: /root/farmer-phase0/20260908-144948/reference/farmer-main/lib/ ไม่ใช่หน้า home แบบย่อที่แก้ก่อนหน้า.

## Product boundary
รักษา farmer-main หน้าแรก/งาน/การเงิน/เชื้อเพลิง/ตั้งค่า. เริ่มข้อมูลใหม่ ไม่มี Firebase import ไม่ใช้ UI สมุดไร่นา. API/DB/volumes แยกจากระบบเดิม; ชื่อ stack farmer-main, staging เสนอ 8090/8091 (ว่าง ณ การตรวจระยะ 0 ต้องตรวจซ้ำก่อน deploy). ไม่ต้องมี farm/farmer organization hierarchy ใน API นี้. เก็บ SSH key จนผู้ใช้สั่งถอน.

## Transport
Base /api/v1. Auth email/password ตาม auth_screen.dart ต้นฉบับ. JSON camelCase; DB snake_case. ห้ามรับ ownerUserId/role จาก body. UUID identifiers; timestamps UTC ISO8601, business dates YYYY-MM-DD แสดง Asia/Bangkok. เงิน JSON number 2 ตำแหน่ง, DB numeric และ Decimal arithmetic. invalid date/number → 422 ไม่ใช้ now/0 แทนเงียบ ๆ.
CRUD: GET /resource → array, GET /resource/{id} → object, POST →201 object, PATCH →200 object (partial, unknown fields forbidden), DELETE →204. List limit default 50 max 200, offset >=0; stable ordering date DESC,id DESC หรือ name,id. GET response ทั้งหมด scope user. Parent มี children →409 ไม่ cascade ลบประวัติ. Foreign owner →404 แบบเดียวกับ missing. Auth missing/expired →401. Errors {code,message,fieldErrors,requestId}.

## Auth
POST /auth/register {email,password}, password 8–200 chars, normalize email; สร้าง farmer เท่านั้น. POST /auth/login ใช้ fields เดียวกัน. ทั้งคู่คืน {access_token,token_type:"bearer",user:{id,email,role:"farmer"}}. GET /auth/me คืน user shape เดียวกัน. POST /auth/logout revoke session →204. JWT signed, expiry, session revocation; signup/login throttling. ยังไม่สร้างบัญชีผู้ใช้ใน phase 0.

## Resources: response fields / writes
id,createdAt,updatedAt และ derived fields เป็น read-only; ทุกตารางมี owner relation.

| Resource | Fields |
|---|---|
| plots | id,name,area,soil,imageUrl; name nonblank, area >0 หน่วยไร่; soil string; imageUrl nullable server-derived |
| cycles | id,name,plotId,plotName,cropType,plantingMethod,startDate,status; plotName derive จาก plots; status active/completed; default active |
| activities | id,cycleId,type,description,date,createdAt,imageUrl; description optional; type nonblank |
| transactions | id,type,category,item,amount,date,cycleId,fuelRecordId; type income/expense, amount >=0 บาท; item nonblank; cycleId nullable |
| vehicles | id,name,category,licensePlate,color,details; name/category nonblank; licensePlate/color string, details nullable |
| fuel-records | id,vehicleId,date,fuelType,amount,details,odometer,transactionId; amount >=0 บาท, odometer optional >=0 กม.; ไม่ใช่ลิตร |
| tasks | id,name,cycleId,dueDate,status,description; name nonblank, cycleId required; dueDate date; status pending/in_progress/completed |

### Confirmed mappings
- cycles_screen.dart:76–84 เขียน riceType แต่ model cropType อ่านจาก riceType. Contract ใหม่ใช้ cropType เท่านั้น; เปลี่ยน Dart adapter/form ในระยะ UI ไม่รับ aliases สองชื่อแบบกำกวม. ไม่ import legacy records.
- transactions_screen.dart:76–82,162–164 มี cycleId='general'. UI label คง 'ทั่วไป (ไม่เกี่ยวกับรอบผลิต)' แต่ส่ง null; ห้ามสร้าง UUID ปลอมหรือ FK ไป general.
- fuel_records_list_tab.dart:79–86,131 และ transactions_screen.dart:133–139,225 ยืนยัน amount = บาท. ไม่มี liters/unitPrice ใน UI เดิม; ไม่เพิ่มเป็น required. odometer มีใน model แต่ไม่มี input เดิม ให้ optional เท่านั้น.
- schedule_screen.dart:64,115–121: name (ไม่ใช่ title), cycleId,dueDate,status,description. Map labels ยังไม่เริ่ม→pending, กำลังทำ→in_progress, เสร็จแล้ว→completed. ไม่เพิ่ม due time/priority เป็น required.
- activities_screen.dart:165–171: เก็บเกี่ยวทำ cycle completed. API บันทึก activity และ completion ใน transaction เดียว. เพิ่ม completeCycle boolean write-only default false; Flutter ส่ง true เมื่อเลือกเก็บเกี่ยว. ลบ/แก้ activity ไม่ reopen cycle อัตโนมัติ; ใช้ cycle PATCH status โดยตรง.
- เพิ่มพืช/พันธุ์หลายชนิดเป็น extension ระยะต่อไป: v1 cropType free text ตามฟอร์มเดิม; variety optional ไม่บังคับและไม่แทนค่าเดิมด้วย seed สมมติ.

## Finance–fuel integrity (ปรับปรุงจากต้นฉบับ)
ต้นฉบับ transactions_screen.dart:108–146 ใช้ batch แต่สร้าง fuel ID ใหม่ทุกครั้งแม้แก้ transaction และไม่ผูก ID. ห้ามคัดลอก bug นี้.
- POST/PATCH transactions รองรับ fuel:{vehicleId,fuelType,odometer?} เฉพาะ expense. วันที่/amount/details ของ linked fuel derive จาก transaction date/amount/item.
- transaction↔fuel เป็น one-to-one unique และ atomic. Retry Idempotency-Key ผูก user/route/body; same key different body →409.
- PATCH financial amount/date/item sync linked fuel; fuel omitted=unchanged, fuel:null=ลบ linked fuel, supplied=upsert ID เดิม. เปลี่ยน type income ต้องไม่มี fuel.
- PATCH linked fuel amount/date/details sync transaction; DELETE transaction ลบ linked fuel แบบ documented; DELETE linked fuel ลบทั้งคู่ต้อง UI confirmation ชัดเจน.
- POST fuel-records แบบ standalone ตามหน้าเชื้อเพลิง ไม่สร้าง transaction อัตโนมัติ (รักษาพฤติกรรมเดิม). Dashboard expense รวม transactions เท่านั้น; fuelSpend แยกและไม่บวกซ้ำ. UI ระบุ standalone fuel ยังไม่ได้ลงบัญชี.

## Categories
GET /settings/categories → {activityCategories:[],expenseCategories:[],incomeCategories:[],soilTypes:[],plantingTypes:[]}.
PUT /settings/categories/{key} {values:[string,...]} replace list เฉพาะ key whitelist, trimmed unique nonblank; return full object. ยืนยันจาก category_provider.dart:29–34,53–66 และ settings_screen.dart:105–134. UI add/delete เป็น list update; category ที่นำออกจากตัวเลือกไม่ลบข้อความในประวัติ. เก็บ version/If-Match สำหรับ conflict→409 ป้องกัน lost update.
ค่า default ตามต้นฉบับเท่านั้น: activity เตรียมดิน/หว่านปักดำ/ใส่ปุ๋ย/ฉีดพ่นยา/ให้น้ำ/เก็บเกี่ยว/อื่นๆ (ใช้สะกดจาก source ที่เก็บไว้ตรงตัวตอน implementation); expense ปุ๋ย/ยาและสารเคมี/เมล็ดพันธุ์/น้ำมันเชื้อเพลิง/ค่าแรงงาน/ค่าเช่าเครื่องจักร/ค่าบำรุงรักษา/อื่นๆ; income ขายข้าวเปลือก/ขายข้าวสาร/รายรับอื่นๆ; soil ดินเหนียว/ดินทราย/ดินร่วน; planting ปักดำ/หว่านน้ำตม/หว่านข้าวงอก/หว่านแห้ง. ไม่มีรายการธุรกรรม/รถ/แปลงตัวอย่าง.

## Photos
plots_screen.dart และ activities_screen.dart ใช้ gallery/camera, imageQuality 50/maxWidth800, Firebase storage putData(Web)/putFile(mobile), แสดงภาพขยาย. API ใหม่ POST /attachments multipart {parentType:plot|activity,parentId,file}; GET /attachments?parentType=&parentId=, GET /attachments/{id}/content, DELETE /attachments/{id}. Owner chain ก่อนแตะไฟล์, JPEG/PNG/WebP <=10MiB ตรวจ signature/extension, random storage ID, no traversal. Parent ต้องมีจริง. รูปหลักหนึ่งภาพต่อ parent; replace upload สำเร็จก่อนลบรูปเก่า. imageUrl เป็น authenticated content path; Flutter fetch bytes ด้วย bearer ไม่ใช้ public token URL. Upload ล้มต้องแจ้งและรักษาภาพเดิม; metadata+file persistence ต้องทดสอบ. ไม่มี client arbitrary remote imageUrl write.

## Dashboard / reports
GET /dashboard?from=YYYY-MM-DD&to=YYYY-MM-DD (inclusive local business dates, default เดือนปัจจุบัน Asia/Bangkok) → {plots,totalArea,activeCycles,income,expense,profit,fuelSpend,expenseByCategory:[{category,amount}],recentActivities:[],recentFuelRecords:[]}.
plots/totalArea/activeCycles = all current owner inventory; financial totals filter period; recentActivities default latest5 all dates และ fuel latest10 all dates ตามต้นฉบับ. income-expense=profit, no duplicate fuel expense. GET /reports/finance?from=&to=&cycleId= → {income,expense,profit,byCategory,byCycle}; GET /reports/fuel?from=&to=&vehicleId= → {totalAmount,byVehicle,byFuelType}. Aggregate queries server-side ครบทุก row ไม่คิดยอดจาก first page.

## Notifications / offline
Tasks เดิม cancel/reschedule local notification หลัง save, cancel เมื่อ delete. API v1 ไม่ส่ง push; Flutter mobile ใช้ stable numeric ID map แทน hashCode ข้าม sessions. Web แสดง due tasks และแจ้งว่าไม่มี background push. รูป online-only ก่อน; offline JSON queue แยก user, only network errors, idempotency. ไม่มีการแอบนำข้อมูล Firebase หรือสมุดไร่นามาใส่.

## Required validation before completion
Contract tests: request/response→typed model→widget populated/empty/error; test users A/B ครบ list/get/write/foreign FK/aggregate/upload. Regression: general cycle, บาทไม่ลิตร, linked edit ไม่เพิ่ม fuel, retries ไม่ซ้ำ, date boundaries, task label mapping, harvest atomic failure, category deletion preserves history, image failure preserves old image. Phase 0 ตรวจ source เท่านั้น ไม่อ้างว่าการทดสอบเหล่านี้ผ่านแล้ว.

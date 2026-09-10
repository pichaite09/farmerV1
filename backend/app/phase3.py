import uuid
from datetime import date
from decimal import Decimal
from fastapi import APIRouter, Depends, Header, HTTPException, Query, Response
from sqlalchemy import select, desc, func
from sqlalchemy.orm import Session
from app.database import get_db
from app.main import current_session
from app.models import (Transaction, Vehicle, FuelRecord, Task, CategorySetting,
                        ProductionCycle, FieldInspection)
from app.schemas import (TransactionCreate, TransactionPatch, TransactionOut,
 VehicleCreate, VehiclePatch, VehicleOut, FuelCreate, FuelPatch, FuelOut,
 TaskCreate, TaskPatch, TaskOut, CategoriesOut, CategoryUpdate)

router=APIRouter(prefix='/api/v1')
def user(i): return i[1]
def notfound(): raise HTTPException(404,'Resource not found')
def owned(db,m,u,i):
    x=db.scalar(select(m).where(m.id==i,m.owner_id==u.id))
    if x is None: notfound()
    return x
def page(limit,offset):
    if limit<1 or limit>200 or offset<0: raise HTTPException(422,'Invalid pagination')
def cycle(db,u,i): return owned(db,ProductionCycle,u,i)
def tx_out(x): return TransactionOut.model_validate(x)
def fuel_out(x): return FuelOut.model_validate(x)
def vehicle_out(x): return VehicleOut.model_validate(x)
def task_out(db, x):
    payload = TaskOut.model_validate(x).model_dump()
    inspection_id = db.scalar(select(FieldInspection.id).where(
        FieldInspection.follow_up_task_id == x.id,
        FieldInspection.owner_id == x.owner_id,
    ))
    payload['field_inspection_id'] = inspection_id
    payload['is_automatic_follow_up'] = inspection_id is not None
    return payload

def make_fuel(db,u,t, spec, existing=None):
    if spec is None: return None
    v=owned(db,Vehicle,u,spec.vehicle_id)
    f=existing or FuelRecord(owner_id=u.id, transaction_id=t.id)
    f.vehicle_id=v.id; f.date=t.date; f.fuel_type=spec.fuel_type; f.amount=t.amount; f.details=t.item; f.odometer=spec.odometer
    if existing is None: db.add(f)
    db.flush(); t.fuel_record_id=f.id
    return f

def linked(db,t): return db.scalar(select(FuelRecord).where(FuelRecord.transaction_id==t.id))

@router.get('/transactions',response_model=list[TransactionOut])
def list_transactions(limit:int=Query(50),offset:int=Query(0),cycle_id:uuid.UUID|None=None,identity=Depends(current_session),db:Session=Depends(get_db)):
    page(limit,offset); q=select(Transaction).where(Transaction.owner_id==user(identity).id)
    if cycle_id is not None:q=q.where(Transaction.cycle_id==cycle_id)
    return [tx_out(x) for x in db.scalars(q.order_by(desc(Transaction.date),desc(Transaction.id)).limit(limit).offset(offset))]
@router.post('/transactions',status_code=201,response_model=TransactionOut)
def create_transaction(b:TransactionCreate,identity=Depends(current_session),db:Session=Depends(get_db)):
    u=user(identity)
    if b.cycle_id is not None: cycle(db,u,b.cycle_id)
    if b.fuel is not None and b.type!='expense': raise HTTPException(422,'Fuel is only valid for expense')
    t=Transaction(owner_id=u.id,**b.model_dump(exclude={'fuel'})); db.add(t); db.flush()
    if b.fuel: make_fuel(db,u,t,b.fuel)
    db.commit();db.refresh(t);return tx_out(t)
@router.get('/transactions/{i}',response_model=TransactionOut)
def get_transaction(i:uuid.UUID,identity=Depends(current_session),db:Session=Depends(get_db)):return tx_out(owned(db,Transaction,user(identity),i))
@router.patch('/transactions/{i}',response_model=TransactionOut)
def update_transaction(i:uuid.UUID,b:TransactionPatch,identity=Depends(current_session),db:Session=Depends(get_db)):
    u=user(identity);t=owned(db,Transaction,u,i); ch=b.model_dump(exclude_unset=True,exclude={'fuel'})
    if 'cycle_id' in ch and ch['cycle_id'] is not None: cycle(db,u,ch['cycle_id'])
    if 'type' in ch and ch['type']=='income' and (b.fuel is not None or linked(db,t) is not None): raise HTTPException(422,'Fuel is only valid for expense')
    for k,v in ch.items(): setattr(t,k,v)
    f=linked(db,t)
    if b.fuel is not None:
        if t.type!='expense':raise HTTPException(422,'Fuel is only valid for expense')
        make_fuel(db,u,t,b.fuel,f)
    elif 'fuel' in b.model_fields_set and f:
        db.delete(f)
    elif f:
        f.amount=t.amount
        f.date=t.date
        f.details=t.item
    db.commit();db.refresh(t);return tx_out(t)
@router.delete('/transactions/{i}',status_code=204)
def delete_transaction(i:uuid.UUID,identity=Depends(current_session),db:Session=Depends(get_db)):
    t=owned(db,Transaction,user(identity),i);db.delete(t);db.commit();return Response(status_code=204)

@router.get('/vehicles',response_model=list[VehicleOut])
def list_vehicles(limit:int=Query(50),offset:int=Query(0),identity=Depends(current_session),db:Session=Depends(get_db)):
    page(limit,offset);return [vehicle_out(x) for x in db.scalars(select(Vehicle).where(Vehicle.owner_id==user(identity).id).order_by(Vehicle.name,Vehicle.id).limit(limit).offset(offset))]
@router.post('/vehicles',status_code=201,response_model=VehicleOut)
def create_vehicle(b:VehicleCreate,identity=Depends(current_session),db:Session=Depends(get_db)):
    x=Vehicle(owner_id=user(identity).id,**b.model_dump());db.add(x);db.commit();db.refresh(x);return vehicle_out(x)
@router.get('/vehicles/{i}',response_model=VehicleOut)
def get_vehicle(i:uuid.UUID,identity=Depends(current_session),db:Session=Depends(get_db)):return vehicle_out(owned(db,Vehicle,user(identity),i))
@router.patch('/vehicles/{i}',response_model=VehicleOut)
def patch_vehicle(i:uuid.UUID,b:VehiclePatch,identity=Depends(current_session),db:Session=Depends(get_db)):
    x=owned(db,Vehicle,user(identity),i)
    for k,v in b.model_dump(exclude_unset=True).items():setattr(x,k,v)
    db.commit();db.refresh(x);return vehicle_out(x)
@router.delete('/vehicles/{i}',status_code=204)
def delete_vehicle(i:uuid.UUID,identity=Depends(current_session),db:Session=Depends(get_db)):
    x=owned(db,Vehicle,user(identity),i)
    if db.scalar(select(FuelRecord.id).where(FuelRecord.vehicle_id==x.id)):raise HTTPException(409,'Vehicle has fuel records')
    db.delete(x);db.commit();return Response(status_code=204)

@router.get('/fuel-records',response_model=list[FuelOut])
def list_fuel(limit:int=Query(50),offset:int=Query(0),vehicle_id:uuid.UUID|None=None,identity=Depends(current_session),db:Session=Depends(get_db)):
    page(limit,offset);q=select(FuelRecord).where(FuelRecord.owner_id==user(identity).id)
    if vehicle_id:q=q.where(FuelRecord.vehicle_id==vehicle_id)
    return [fuel_out(x) for x in db.scalars(q.order_by(desc(FuelRecord.date),desc(FuelRecord.id)).limit(limit).offset(offset))]
@router.post('/fuel-records',status_code=201,response_model=FuelOut)
def create_fuel(b:FuelCreate,identity=Depends(current_session),db:Session=Depends(get_db)):
    u=user(identity);owned(db,Vehicle,u,b.vehicle_id);x=FuelRecord(owner_id=u.id,**b.model_dump());db.add(x);db.commit();db.refresh(x);return fuel_out(x)
@router.get('/fuel-records/{i}',response_model=FuelOut)
def get_fuel(i:uuid.UUID,identity=Depends(current_session),db:Session=Depends(get_db)):return fuel_out(owned(db,FuelRecord,user(identity),i))
@router.patch('/fuel-records/{i}',response_model=FuelOut)
def patch_fuel(i:uuid.UUID,b:FuelPatch,identity=Depends(current_session),db:Session=Depends(get_db)):
    u=user(identity);x=owned(db,FuelRecord,u,i);ch=b.model_dump(exclude_unset=True)
    if 'vehicle_id' in ch:owned(db,Vehicle,u,ch['vehicle_id'])
    t=x.transaction_id
    for k,v in ch.items():setattr(x,k,v)
    if t:
        t=db.get(Transaction,t);t.amount=x.amount;t.date=x.date;t.item=x.details or t.item
    db.commit();db.refresh(x);return fuel_out(x)
@router.delete('/fuel-records/{i}',status_code=204)
def delete_fuel(i:uuid.UUID,identity=Depends(current_session),db:Session=Depends(get_db)):
    x=owned(db,FuelRecord,user(identity),i);t=x.transaction_id
    if t:db.delete(db.get(Transaction,t))
    else:db.delete(x)
    db.commit();return Response(status_code=204)

@router.get('/tasks',response_model=list[TaskOut])
def list_tasks(limit:int=Query(50),offset:int=Query(0),cycle_id:uuid.UUID|None=Query(None, alias='cycleId'),identity=Depends(current_session),db:Session=Depends(get_db)):
    page(limit,offset);q=select(Task).where(Task.owner_id==user(identity).id)
    if cycle_id is not None:q=q.where(Task.cycle_id==cycle_id)
    return [task_out(db, x) for x in db.scalars(q.order_by(Task.due_date,Task.id).limit(limit).offset(offset))]
@router.post('/tasks',status_code=201,response_model=TaskOut)
def create_task(b:TaskCreate,identity=Depends(current_session),db:Session=Depends(get_db)):
    u=user(identity);cycle(db,u,b.cycle_id);x=Task(owner_id=u.id,**b.model_dump());db.add(x);db.commit();db.refresh(x);return task_out(db, x)
@router.get('/tasks/{i}',response_model=TaskOut)
def get_task(i:uuid.UUID,identity=Depends(current_session),db:Session=Depends(get_db)):return task_out(db, owned(db,Task,user(identity),i))
@router.patch('/tasks/{i}',response_model=TaskOut)
def patch_task(i:uuid.UUID,b:TaskPatch,identity=Depends(current_session),db:Session=Depends(get_db)):
    u=user(identity);x=owned(db,Task,u,i);ch=b.model_dump(exclude_unset=True)
    if 'cycle_id' in ch:cycle(db,u,ch['cycle_id'])
    for k,v in ch.items():setattr(x,k,v)
    db.commit();db.refresh(x);return task_out(db, x)
@router.delete('/tasks/{i}',status_code=204)
def delete_task(i:uuid.UUID,identity=Depends(current_session),db:Session=Depends(get_db)):
    db.delete(owned(db,Task,user(identity),i));db.commit();return Response(status_code=204)

DEFAULTS={'activityCategories':['เตรียมดิน','หว่านปักดำ','ใส่ปุ๋ย','ฉีดพ่นยา','ให้น้ำ','เก็บเกี่ยว','อื่นๆ'],'expenseCategories':['ปุ๋ย','ยาและสารเคมี','เมล็ดพันธุ์','น้ำมันเชื้อเพลิง','ค่าแรงงาน','ค่าเช่าเครื่องจักร','ค่าบำรุงรักษา','อื่นๆ'],'incomeCategories':['ขายข้าวเปลือก','ขายข้าวสาร','รายรับอื่นๆ'],'soilTypes':['ดินเหนียว','ดินทราย','ดินร่วน'],'plantingTypes':['ปักดำ','หว่านน้ำตม','หว่านข้าวงอก','หว่านแห้ง'],'cropTypes':['ข้าว','ข้าวโพด','มันสำปะหลัง','อ้อย','ผัก','ผลไม้','อื่นๆ'],'vehicleCategories':['รถยนต์','รถมอเตอร์ไซค์','รถไถนั่งขับ','รถไถเดินตาม']}
def categories(db,u):
    out={}; rows={x.key:x for x in db.scalars(select(CategorySetting).where(CategorySetting.owner_id==u.id))}
    for k,v in DEFAULTS.items():out[k]=rows[k].values if k in rows else v
    return out
@router.get('/settings/categories',response_model=CategoriesOut)
def get_categories(identity=Depends(current_session),db:Session=Depends(get_db)):return categories(db,user(identity))
@router.put('/settings/categories/{key}',response_model=CategoriesOut)
def put_category(key:str,b:CategoryUpdate,if_match:str|None=Header(None),identity=Depends(current_session),db:Session=Depends(get_db)):
    if key not in DEFAULTS:raise HTTPException(404,'Unknown category key')
    u=user(identity);x=db.scalar(select(CategorySetting).where(CategorySetting.owner_id==u.id,CategorySetting.key==key)); current=x.version if x else 1
    if if_match is not None and if_match.strip('"')!=str(current):raise HTTPException(409,'Category version conflict')
    vals=list(dict.fromkeys(v.strip() for v in b.values))
    if any(not v for v in vals):raise HTTPException(422,'Category values must be nonblank')
    if x:x.values=vals;x.version+=1
    else:x=CategorySetting(owner_id=u.id,key=key,values=vals,version=2);db.add(x)
    db.commit();return categories(db,u)

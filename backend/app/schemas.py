from __future__ import annotations
import uuid
from datetime import date as DateType, datetime
from decimal import Decimal
from pydantic import BaseModel, ConfigDict, field_validator
from typing import Any
class APIModel(BaseModel):
    model_config=ConfigDict(alias_generator=lambda s: ''.join([s.split('_')[0]]+[p.title() for p in s.split('_')[1:]]),populate_by_name=True,from_attributes=True,extra='forbid')
class PlotCreate(APIModel):
    name:str;area:Decimal;soil:str|None=None;image_url:str|None=None
    @field_validator('name','soil')
    @classmethod
    def text(cls,v):
        if v is not None and not v.strip():raise ValueError('must not be blank')
        return v.strip() if isinstance(v,str) else v
    @field_validator('area')
    @classmethod
    def pos(cls,v):
        if v<=0:raise ValueError('must be greater than 0')
        return v
    @field_validator('image_url')
    @classmethod
    def noimg(cls,v):
        if v is not None:raise ValueError('imageUrl is server-derived')
        return v
class PlotPatch(PlotCreate):
    name:str|None=None;area:Decimal|None=None
    @field_validator('area')
    @classmethod
    def ppos(cls,v):
        if v is not None and v<=0:raise ValueError('must be greater than 0')
        return v
class PlotOut(APIModel):
    id:uuid.UUID;name:str;area:Decimal;soil:str|None;image_url:str|None;created_at:datetime;updated_at:datetime
class CycleCreate(APIModel):
    name:str;plot_id:uuid.UUID;crop_type:str;variety:str;planting_method:str;start_date:DateType;status:str='active'
    @field_validator('name','crop_type','variety','planting_method')
    @classmethod
    def rt(cls,v):
        if not v.strip():raise ValueError('must not be blank')
        return v.strip()
    @field_validator('status')
    @classmethod
    def cv(cls,v):
        if v not in ('active','completed'):raise ValueError('invalid status')
        return v
class CyclePatch(CycleCreate):
    name:str|None=None;plot_id:uuid.UUID|None=None;crop_type:str|None=None;variety:str|None=None;planting_method:str|None=None;start_date:DateType|None=None;status:str|None=None
class CycleOut(APIModel):
    id:uuid.UUID;name:str;plot_id:uuid.UUID;plot_name:str;crop_type:str;variety:str;planting_method:str;start_date:DateType;status:str;created_at:datetime;updated_at:datetime
class ActivityCreate(APIModel):
    cycle_id:uuid.UUID;type:str;description:str|None=None;date:DateType;image_url:str|None=None;complete_cycle:bool=False
    @field_validator('type')
    @classmethod
    def at(cls,v):
        if not v.strip():raise ValueError('must not be blank')
        return v.strip()
    @field_validator('image_url')
    @classmethod
    def ai(cls,v):
        if v is not None:raise ValueError('imageUrl is server-derived')
        return v
class ActivityPatch(APIModel):
    cycle_id:uuid.UUID|None=None;type:str|None=None;description:str|None=None;date:DateType|None=None;image_url:str|None=None
class ActivityOut(APIModel):
    id:uuid.UUID;cycle_id:uuid.UUID;type:str;description:str|None;date:DateType;created_at:datetime;image_url:str|None

class FieldInspectionCreate(APIModel):
    plot_id: uuid.UUID
    cycle_id: uuid.UUID | None = None
    inspection_date: DateType
    overall_status: str
    checklist: dict[str, Any]
    notes: str | None = None
    recommendation: str | None = None
    follow_up_required: bool = False
    follow_up_date: DateType | None = None

    @field_validator('overall_status')
    @classmethod
    def status_not_blank(cls, value):
        if not value.strip():
            raise ValueError('must not be blank')
        return value.strip()

class FieldInspectionPatch(APIModel):
    plot_id: uuid.UUID | None = None
    cycle_id: uuid.UUID | None = None
    inspection_date: DateType | None = None
    overall_status: str | None = None
    checklist: dict[str, Any] | None = None
    notes: str | None = None
    recommendation: str | None = None
    follow_up_required: bool | None = None
    follow_up_date: DateType | None = None

    @field_validator('overall_status')
    @classmethod
    def patch_status_not_blank(cls, value):
        if value is not None and not value.strip():
            raise ValueError('must not be blank')
        return value.strip() if value is not None else value

class FieldInspectionOut(APIModel):
    id: uuid.UUID
    plot_id: uuid.UUID
    cycle_id: uuid.UUID | None
    inspection_date: DateType
    overall_status: str
    checklist: dict[str, Any]
    notes: str | None
    recommendation: str | None
    follow_up_required: bool
    follow_up_date: DateType | None
    follow_up_task_id: uuid.UUID | None = None
    follow_up_status: str | None = None
    created_at: datetime
    updated_at: datetime

class FuelLink(APIModel):
    vehicle_id:uuid.UUID;fuel_type:str;odometer:Decimal|None=None
    @field_validator('fuel_type')
    @classmethod
    def fl(cls,v):
        if not v.strip():raise ValueError('must not be blank')
        return v.strip()
    @field_validator('odometer')
    @classmethod
    def od(cls,v):
        if v is not None and v<0:raise ValueError('must be >= 0')
        return v
class TransactionCreate(APIModel):
    type:str;category:str;item:str;amount:Decimal;date:DateType;cycle_id:uuid.UUID|None=None;fuel:FuelLink|None=None
    @field_validator('type')
    @classmethod
    def tt(cls,v):
        if v not in ('income','expense'):raise ValueError('invalid type')
        return v
    @field_validator('category','item')
    @classmethod
    def tx(cls,v):
        if not v.strip():raise ValueError('must not be blank')
        return v.strip()
    @field_validator('amount')
    @classmethod
    def money(cls,v):
        if v<0:raise ValueError('must be >= 0')
        return v.quantize(Decimal('0.01'))
class TransactionPatch(TransactionCreate):
    type:str|None=None;category:str|None=None;item:str|None=None;amount:Decimal|None=None;date:DateType|None=None;cycle_id:uuid.UUID|None=None;fuel:FuelLink|None=None
class TransactionOut(APIModel):
    id:uuid.UUID;type:str;category:str;item:str;amount:Decimal;date:DateType;cycle_id:uuid.UUID|None;fuel_record_id:uuid.UUID|None;created_at:datetime;updated_at:datetime
class VehicleCreate(APIModel):
    name:str;category:str;license_plate:str|None=None;color:str|None=None;details:str|None=None
    @field_validator('name','category')
    @classmethod
    def vt(cls,v):
        if not v.strip():raise ValueError('must not be blank')
        return v.strip()
class VehiclePatch(VehicleCreate):
    name:str|None=None;category:str|None=None
class VehicleOut(APIModel):
    id:uuid.UUID;name:str;category:str;license_plate:str|None;color:str|None;details:str|None;created_at:datetime;updated_at:datetime
class FuelCreate(APIModel):
    vehicle_id:uuid.UUID;date:DateType;fuel_type:str;amount:Decimal;details:str|None=None;odometer:Decimal|None=None
    @field_validator('amount','odometer')
    @classmethod
    def nn(cls,v):
        if v is not None and v<0:raise ValueError('must be >= 0')
        return v
class FuelPatch(FuelCreate):
    vehicle_id:uuid.UUID|None=None;date:DateType|None=None;fuel_type:str|None=None;amount:Decimal|None=None
class FuelOut(APIModel):
    id:uuid.UUID;vehicle_id:uuid.UUID;date:DateType;fuel_type:str;amount:Decimal;details:str|None;odometer:Decimal|None;transaction_id:uuid.UUID|None;created_at:datetime;updated_at:datetime
class TaskCreate(APIModel):
    name:str;cycle_id:uuid.UUID;due_date:DateType;status:str='pending';description:str|None=None
    @field_validator('name')
    @classmethod
    def tn(cls,v):
        if not v.strip():raise ValueError('must not be blank')
        return v.strip()
    @field_validator('status')
    @classmethod
    def st(cls,v):
        if v not in ('pending','in_progress','completed'):raise ValueError('invalid status')
        return v
class TaskPatch(TaskCreate):
    name:str|None=None;cycle_id:uuid.UUID|None=None;due_date:DateType|None=None;status:str|None=None
class TaskOut(APIModel):
    id:uuid.UUID;name:str;cycle_id:uuid.UUID;due_date:DateType;status:str;description:str|None;created_at:datetime;updated_at:datetime
    field_inspection_id: uuid.UUID | None = None
    is_automatic_follow_up: bool = False
class NotificationOut(APIModel):
    id:uuid.UUID;task_id:uuid.UUID;task_name:str;cycle_name:str;plot_name:str;due_date:DateType;kind:str;title:str;body:str;created_at:datetime;read_at:datetime|None
class PushSubscriptionKeys(APIModel):
    p256dh: str
    auth: str

class PushSubscriptionCreate(APIModel):
    endpoint: str
    keys: PushSubscriptionKeys

class PushSubscriptionPatch(APIModel):
    endpoint: str | None = None
    keys: PushSubscriptionKeys | None = None

class PushSubscriptionOut(APIModel):
    id: uuid.UUID
    endpoint: str
    keys: PushSubscriptionKeys
    created_at: datetime
    updated_at: datetime

class CategoriesOut(APIModel):
    activity_categories:list[str];expense_categories:list[str];income_categories:list[str];soil_types:list[str];planting_types:list[str];crop_types:list[str];vehicle_categories:list[str]
class CategoryUpdate(APIModel): values:list[str]

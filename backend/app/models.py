import uuid
from datetime import date, datetime
from decimal import Decimal
from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint, func, JSON
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base

class User(Base):
    __tablename__ = 'users'
    __table_args__ = (CheckConstraint("role = 'farmer'", name='users_farmer_only'),)
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    first_name: Mapped[str | None] = mapped_column(String(100))
    last_name: Mapped[str | None] = mapped_column(String(100))
    birth_date: Mapped[date | None] = mapped_column(Date)
    house_number: Mapped[str | None] = mapped_column(String(100))
    subdistrict: Mapped[str | None] = mapped_column(String(150))
    district: Mapped[str | None] = mapped_column(String(150))
    province: Mapped[str | None] = mapped_column(String(150))
    phone: Mapped[str | None] = mapped_column(String(30))
    password_hash: Mapped[str] = mapped_column(String(512))
    role: Mapped[str] = mapped_column(String(16), default='farmer')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

class AuthSession(Base):
    __tablename__ = 'sessions'
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

class AuthThrottle(Base):
    __tablename__ = 'auth_throttles'
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    window_start: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column()

class Plot(Base):
    __tablename__ = 'plots'
    __table_args__ = (CheckConstraint('area > 0', name='plots_area_positive'),)
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('users.id', ondelete='RESTRICT'), index=True)
    name: Mapped[str] = mapped_column(String(200))
    area: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    soil: Mapped[str | None] = mapped_column(String(100))
    image_url: Mapped[str | None] = mapped_column(String(1000))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class ProductionCycle(Base):
    __tablename__ = 'production_cycles'
    __table_args__ = (CheckConstraint("status IN ('active','completed')", name='cycles_status_valid'),)
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('users.id', ondelete='RESTRICT'), index=True)
    plot_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('plots.id', ondelete='RESTRICT'), index=True)
    name: Mapped[str] = mapped_column(String(200))
    crop_type: Mapped[str] = mapped_column(String(200))
    variety: Mapped[str] = mapped_column(String(200), server_default='')
    planting_method: Mapped[str] = mapped_column(String(200))
    start_date: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(16), default='active')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class Transaction(Base):
    __tablename__='transactions'
    id: Mapped[uuid.UUID]=mapped_column(primary_key=True,default=uuid.uuid4); owner_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('users.id',ondelete='RESTRICT'),index=True)
    type: Mapped[str]=mapped_column(String(16)); category: Mapped[str]=mapped_column(String(200)); item: Mapped[str]=mapped_column(String(300)); amount: Mapped[Decimal]=mapped_column(Numeric(14,2)); date: Mapped[date]=mapped_column(Date); cycle_id: Mapped[uuid.UUID|None]=mapped_column(ForeignKey('production_cycles.id',ondelete='RESTRICT')); fuel_record_id: Mapped[uuid.UUID|None]=mapped_column(ForeignKey('fuel_records.id',ondelete='SET NULL'))
    created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),server_default=func.now()); updated_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),server_default=func.now(),onupdate=func.now())
class Vehicle(Base):
    __tablename__='vehicles'
    id: Mapped[uuid.UUID]=mapped_column(primary_key=True,default=uuid.uuid4);owner_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('users.id',ondelete='RESTRICT'),index=True);name: Mapped[str]=mapped_column(String(200));category: Mapped[str]=mapped_column(String(200));license_plate: Mapped[str|None]=mapped_column(String(100));color: Mapped[str|None]=mapped_column(String(100));details: Mapped[str|None]=mapped_column(Text);created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),server_default=func.now());updated_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),server_default=func.now(),onupdate=func.now())
class FuelRecord(Base):
    __tablename__='fuel_records'
    id: Mapped[uuid.UUID]=mapped_column(primary_key=True,default=uuid.uuid4);owner_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('users.id',ondelete='RESTRICT'),index=True);vehicle_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('vehicles.id',ondelete='RESTRICT'));date: Mapped[date]=mapped_column(Date);fuel_type: Mapped[str]=mapped_column(String(100));amount: Mapped[Decimal]=mapped_column(Numeric(14,2));details: Mapped[str|None]=mapped_column(Text);odometer: Mapped[Decimal|None]=mapped_column(Numeric(14,2));transaction_id: Mapped[uuid.UUID|None]=mapped_column(ForeignKey('transactions.id',ondelete='CASCADE'),unique=True);created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),server_default=func.now());updated_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),server_default=func.now(),onupdate=func.now())
class Task(Base):
    __tablename__='tasks'
    id: Mapped[uuid.UUID]=mapped_column(primary_key=True,default=uuid.uuid4);owner_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('users.id',ondelete='RESTRICT'),index=True);name: Mapped[str]=mapped_column(String(200));cycle_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('production_cycles.id',ondelete='RESTRICT'));due_date: Mapped[date]=mapped_column(Date);status: Mapped[str]=mapped_column(String(20));description: Mapped[str|None]=mapped_column(Text);created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),server_default=func.now());updated_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),server_default=func.now(),onupdate=func.now())
class CategorySetting(Base):
    __tablename__='category_settings'
    id: Mapped[uuid.UUID]=mapped_column(primary_key=True,default=uuid.uuid4);owner_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('users.id',ondelete='CASCADE'));key: Mapped[str]=mapped_column(String(40));values: Mapped[list]=mapped_column(JSON);version: Mapped[int]=mapped_column(default=1)

class Activity(Base):
    __tablename__ = 'activities'
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('users.id', ondelete='RESTRICT'), index=True)
    cycle_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('production_cycles.id', ondelete='RESTRICT'), index=True)
    type: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text)
    date: Mapped[date] = mapped_column(Date)
    image_url: Mapped[str | None] = mapped_column(String(1000))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class FieldInspection(Base):
    __tablename__ = 'field_inspections'
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('users.id', ondelete='RESTRICT'), index=True)
    plot_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('plots.id', ondelete='RESTRICT'), index=True)
    cycle_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey('production_cycles.id', ondelete='RESTRICT'), index=True)
    inspection_date: Mapped[date] = mapped_column(Date)
    overall_status: Mapped[str] = mapped_column(String(32))
    checklist: Mapped[dict] = mapped_column(JSON)
    notes: Mapped[str | None] = mapped_column(Text)
    recommendation: Mapped[str | None] = mapped_column(Text)
    follow_up_required: Mapped[bool] = mapped_column(default=False, server_default='false')
    follow_up_date: Mapped[date | None] = mapped_column(Date)
    follow_up_task_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey('tasks.id', ondelete='SET NULL'), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class Attachment(Base):
    __tablename__ = 'attachments'
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    parent_type: Mapped[str] = mapped_column(String(16))
    parent_id: Mapped[uuid.UUID] = mapped_column()
    storage_name: Mapped[str] = mapped_column(String(100), unique=True)
    content_type: Mapped[str] = mapped_column(String(32))
    size_bytes: Mapped[int] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

class PushSubscription(Base):
    __tablename__ = 'push_subscriptions'
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    endpoint: Mapped[str] = mapped_column(String(2048), unique=True)
    p256dh: Mapped[str] = mapped_column(String(512))
    auth: Mapped[str] = mapped_column(String(512))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class Notification(Base):
    __tablename__ = 'notifications'
    __table_args__ = (UniqueConstraint('owner_id', 'task_id', 'due_date', name='uq_notification_owner_task_due_date'),)
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    task_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('tasks.id', ondelete='CASCADE'), index=True)
    due_date: Mapped[date] = mapped_column(Date)
    kind: Mapped[str] = mapped_column(String(64))
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    dismissed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

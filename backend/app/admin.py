from datetime import date, datetime, time, timezone
from pathlib import Path
from typing import Literal
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from sqlalchemy import func, select, update, literal, union_all
from sqlalchemy.orm import Session

from app.database import get_db, settings
from app.main import admin_session
from app.models import (
    Activity, Attachment, FieldInspection, FuelRecord, Plot, ProductionCycle,
    Task, Transaction, User, AuthSession, Notification, Vehicle, Announcement, AnnouncementRecipient, AuditLog,
)
from app.schemas import AdminDashboardOut, AnnouncementCreate, AnnouncementOut, AnnouncementSummaryOut, AdminUserPatch
from app.push import enqueue_push_outbox

router = APIRouter(prefix='/api/v1/admin', tags=['admin'])
RecordType = Literal['activity', 'field_inspection', 'task', 'production_cycle', 'plot', 'transaction', 'fuel_record']
MODELS = {
    'activity': Activity, 'field_inspection': FieldInspection, 'task': Task,
    'production_cycle': ProductionCycle, 'plot': Plot,
    'transaction': Transaction, 'fuel_record': FuelRecord,
}
DATE_COLUMNS = {
    'activity': Activity.date, 'field_inspection': FieldInspection.inspection_date,
    'task': Task.due_date, 'production_cycle': ProductionCycle.start_date,
    'plot': Plot.created_at, 'transaction': Transaction.date, 'fuel_record': FuelRecord.date,
}
SUPPORTED_CONTEXT_FILTERS = {
    'activity': {'plot', 'cycle'},
    'field_inspection': {'plot', 'cycle'},
    'task': {'plot', 'cycle'},
    'production_cycle': {'plot', 'cycle'},
    'plot': {'plot'},
    'transaction': {'plot', 'cycle'},
    'fuel_record': {'plot', 'cycle'},
}


def _created_range(frm: date | None, to: date | None):
    start = datetime.combine(frm, time.min, tzinfo=timezone.utc) if frm else None
    end = datetime.combine(to, time.max, tzinfo=timezone.utc) if to else None
    return start, end


def _count(db: Session, model, start: datetime | None, end: datetime | None) -> int:
    query = select(func.count()).select_from(model)
    if start is not None:
        query = query.where(model.created_at >= start)
    if end is not None:
        query = query.where(model.created_at <= end)
    return int(db.scalar(query) or 0)


@router.get('/dashboard', response_model=AdminDashboardOut)
def admin_dashboard(
    frm: date | None = Query(None, alias='from'), to: date | None = Query(None),
    identity=Depends(admin_session), db: Session = Depends(get_db),
):
    if frm and to and frm > to:
        raise HTTPException(422, 'from must not exceed to')
    start, end = _created_range(frm, to)
    return {'from_date': frm, 'to': to, 'counts': {
        'users': _count(db, User, start, end), 'plots': _count(db, Plot, start, end),
        'cycles': _count(db, ProductionCycle, start, end), 'activities': _count(db, Activity, start, end),
        'tasks': _count(db, Task, start, end), 'notifications': _count(db, Notification, start, end),
    }}


def _pagination(limit: int, offset: int):
    if not 1 <= limit <= 100 or offset < 0 or offset > 100_000:
        raise HTTPException(422, 'limit must be 1..100 and offset must be 0..100000')


def _context(db: Session, rows):
    owner_ids = {r.owner_id for r in rows}
    plot_ids = {getattr(r, 'plot_id', None) for r in rows} - {None}
    cycle_ids = {getattr(r, 'cycle_id', None) for r in rows} - {None}
    cycle_ids |= {r.id for r in rows if isinstance(r, ProductionCycle)}
    transaction_ids = {getattr(r, 'transaction_id', None) for r in rows} - {None}
    users = {u.id: u for u in db.scalars(select(User).where(User.id.in_(owner_ids))).all()} if owner_ids else {}
    transactions = {t.id: t for t in db.scalars(select(Transaction).where(Transaction.id.in_(transaction_ids))).all()} if transaction_ids else {}
    cycle_ids |= {t.cycle_id for t in transactions.values()} - {None}
    cycles = {c.id: c for c in db.scalars(select(ProductionCycle).where(ProductionCycle.id.in_(cycle_ids))).all()} if cycle_ids else {}
    plot_ids |= {c.plot_id for c in cycles.values()}
    plots = {p.id: p for p in db.scalars(select(Plot).where(Plot.id.in_(plot_ids))).all()} if plot_ids else {}
    return users, plots, cycles, transactions


def _record_cycle(cycles, transactions, row):
    cycle_id = getattr(row, 'cycle_id', None)
    if cycle_id is None:
        cycle_id = getattr(transactions.get(getattr(row, 'transaction_id', None)), 'cycle_id', None)
    return cycles.get(cycle_id)


def _record_plot(plots, cycles, transactions, row):
    plot_id = getattr(row, 'plot_id', None)
    if plot_id is None:
        cycle = _record_cycle(cycles, transactions, row)
        plot_id = getattr(cycle, 'plot_id', None)
    return plots.get(plot_id)


def _safe_user(user):
    if user is None:
        return None
    return {'id': user.id, 'email': user.email, 'firstName': user.first_name, 'lastName': user.last_name, 'role': user.role}


def _safe_context(plot, cycle):
    return ({'id': plot.id, 'name': plot.name, 'area': plot.area} if plot else None,
            {'id': cycle.id, 'name': cycle.name, 'cropType': cycle.crop_type, 'status': cycle.status} if cycle else None)


def _attachments(db: Session, record_type: str, ids, owner_id=None):
    if not ids:
        return {}
    query = select(Attachment).where(Attachment.parent_type == record_type, Attachment.parent_id.in_(ids))
    if owner_id is not None:
        query = query.where(Attachment.owner_id == owner_id)
    rows = db.scalars(query).all()
    result = {}
    for row in rows:
        result.setdefault(row.parent_id, []).append({
            'id': row.id, 'contentType': row.content_type,
            'sizeBytes': row.size_bytes, 'createdAt': row.created_at,
        })
    return result


_ADMIN_IMAGE_TYPES = frozenset({'image/jpeg', 'image/png', 'image/webp'})
_ADMIN_IMAGE_MAX_BYTES = 10 * 1024 * 1024


@router.get('/attachments/{attachment_id}/content')
def admin_attachment_content(
    attachment_id: uuid.UUID,
    identity=Depends(admin_session),
    db: Session = Depends(get_db),
):
    """Serve an image only after the admin RBAC check and path validation."""
    row = db.scalar(select(Attachment).where(Attachment.id == attachment_id))
    if row is None:
        raise HTTPException(404, 'Attachment not found')
    if row.content_type not in _ADMIN_IMAGE_TYPES:
        raise HTTPException(415, 'Attachment is not an allowed image')

    root = Path(settings.attachment_storage_path).resolve()
    candidate = (root / row.storage_name).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        raise HTTPException(404, 'Attachment content not found')
    if not candidate.is_file():
        raise HTTPException(404, 'Attachment content not found')
    try:
        size = candidate.stat().st_size
    except OSError:
        raise HTTPException(404, 'Attachment content not found')
    if size > _ADMIN_IMAGE_MAX_BYTES or row.size_bytes > _ADMIN_IMAGE_MAX_BYTES:
        raise HTTPException(413, 'Attachment content is too large')
    return FileResponse(candidate, media_type=row.content_type, headers={'Cache-Control': 'no-store'})


def _row(record_type, row, user, plot, cycle, attachments):
    plot, cycle = _safe_context(plot, cycle)
    if record_type == 'plot' and plot is None:
        plot = {'id': row.id, 'name': row.name, 'area': row.area}
    if record_type == 'production_cycle' and cycle is None:
        cycle = {'id': row.id, 'name': row.name, 'cropType': row.crop_type, 'status': row.status}
    fields = {'id': row.id, 'type': record_type, 'createdAt': row.created_at, 'recorder': _safe_user(user), 'plot': plot, 'cycle': cycle, 'attachments': attachments}
    if record_type == 'activity': fields.update(activityType=row.type, description=row.description, date=row.date)
    elif record_type == 'field_inspection': fields.update(inspectionDate=row.inspection_date, overallStatus=row.overall_status, notes=row.notes, followUpRequired=row.follow_up_required)
    elif record_type == 'task': fields.update(name=row.name, dueDate=row.due_date, status=row.status, description=row.description)
    elif record_type == 'production_cycle': fields.update(name=row.name, cropType=row.crop_type, variety=row.variety, startDate=row.start_date, status=row.status)
    elif record_type == 'plot': fields.update(name=row.name, area=row.area, soil=row.soil)
    elif record_type == 'transaction': fields.update(transactionType=row.type, category=row.category, item=row.item, amount=row.amount, date=row.date)
    elif record_type == 'fuel_record': fields.update(date=row.date, fuelType=row.fuel_type, amount=row.amount, vehicleId=row.vehicle_id, details=row.details)
    return fields


def _query_records(db, record_type, frm, to, owner, plot_id, cycle_id):
    model = MODELS[record_type]
    requested_filters = ({'plot'} if plot_id else set()) | ({'cycle'} if cycle_id else set())
    unsupported = requested_filters - SUPPORTED_CONTEXT_FILTERS[record_type]
    if unsupported:
        names = ', '.join(sorted(unsupported))
        raise HTTPException(422, f"{record_type} does not support {names} filter")
    query = select(model)
    if owner is not None: query = query.where(model.owner_id == owner)
    column = DATE_COLUMNS[record_type]
    if record_type == 'plot':
        start, end = _created_range(frm, to)
        if start: query = query.where(column >= start)
        if end: query = query.where(column <= end)
    else:
        if frm: query = query.where(column >= frm)
        if to: query = query.where(column <= to)
    if plot_id:
        if record_type == 'plot':
            query = query.where(model.id == plot_id)
        elif record_type in ('field_inspection', 'production_cycle'):
            query = query.where(model.plot_id == plot_id)
        elif record_type in ('activity', 'task', 'transaction'):
            query = query.join(ProductionCycle, model.cycle_id == ProductionCycle.id).where(ProductionCycle.plot_id == plot_id)
        elif record_type == 'fuel_record':
            query = query.join(Transaction, FuelRecord.transaction_id == Transaction.id).join(
                ProductionCycle, Transaction.cycle_id == ProductionCycle.id,
            ).where(ProductionCycle.plot_id == plot_id)
    if cycle_id:
        if record_type == 'production_cycle':
            query = query.where(model.id == cycle_id)
        elif record_type == 'fuel_record':
            if not plot_id:
                query = query.join(Transaction, FuelRecord.transaction_id == Transaction.id)
            query = query.where(Transaction.cycle_id == cycle_id)
        elif hasattr(model, 'cycle_id'):
            query = query.where(model.cycle_id == cycle_id)
    return query


def _cycle_detail_rows(db: Session, cycle: ProductionCycle):
    owner_id = cycle.owner_id
    plot = db.get(Plot, cycle.plot_id)
    owner = db.get(User, owner_id)
    queries = {
        'activities': select(Activity).where(Activity.owner_id == owner_id, Activity.cycle_id == cycle.id),
        'fieldInspections': select(FieldInspection).where(
            FieldInspection.owner_id == owner_id, FieldInspection.cycle_id == cycle.id,
        ),
        'tasks': select(Task).where(Task.owner_id == owner_id, Task.cycle_id == cycle.id),
        'transactions': select(Transaction).where(
            Transaction.owner_id == owner_id,
            Transaction.cycle_id == cycle.id,
            Transaction.fuel_record_id.is_(None),
        ),
    }
    rows = {key: list(db.scalars(query).all()) for key, query in queries.items()}
    # Fuel records are linked through their transaction's cycle.  Joining here
    # prevents an unrelated/unassigned fuel row from leaking into the cycle.
    rows['fuelRecords'] = list(db.scalars(
        select(FuelRecord).join(Transaction, FuelRecord.transaction_id == Transaction.id).where(
            FuelRecord.owner_id == owner_id,
            Transaction.owner_id == owner_id,
            Transaction.cycle_id == cycle.id,
        ).order_by(FuelRecord.date, FuelRecord.id)
    ).all())
    record_types = {
        'activities': 'activity', 'fieldInspections': 'field_inspection',
        'tasks': 'task', 'transactions': 'transaction', 'fuelRecords': 'fuel_record',
    }
    serialized = {}
    for key, values in rows.items():
        kind = record_types[key]
        attachments = _attachments(db, kind, [row.id for row in values], owner_id=owner_id)
        serialized[key] = [_row(kind, row, owner, plot, cycle, attachments.get(row.id, [])) for row in values]
    timeline = [item for key in ('activities', 'fieldInspections', 'tasks', 'transactions', 'fuelRecords') for item in serialized[key]]
    timeline.sort(key=lambda item: (str(item.get('date') or item.get('inspectionDate') or item.get('dueDate') or item.get('createdAt') or ''), str(item['id'])), reverse=True)
    return serialized, timeline


@router.get('/production-cycles/{cycle_id}/detail')
def admin_production_cycle_detail(
    cycle_id: uuid.UUID,
    identity=Depends(admin_session),
    db: Session = Depends(get_db),
):
    cycle = db.scalar(select(ProductionCycle).where(ProductionCycle.id == cycle_id))
    if cycle is None:
        raise HTTPException(404, 'Production cycle not found')
    rows, timeline = _cycle_detail_rows(db, cycle)
    cycle_attachments = _attachments(db, 'production_cycle', [cycle.id], owner_id=cycle.owner_id).get(cycle.id, [])
    return {
        'cycle': _row('production_cycle', cycle, db.get(User, cycle.owner_id), db.get(Plot, cycle.plot_id), cycle, cycle_attachments),
        'counts': {key: len(value) for key, value in rows.items()},
        **rows,
        'timeline': timeline,
    }


@router.get('/records')
def list_admin_records(
    record_type: RecordType | Literal['all'] = Query('all', alias='type'),
    frm: date | None = Query(None, alias='from'), to: date | None = Query(None),
    owner: uuid.UUID | None = Query(None), plot: uuid.UUID | None = Query(None), cycle: uuid.UUID | None = Query(None),
    limit: int = Query(50), offset: int = Query(0),
    identity=Depends(admin_session), db: Session = Depends(get_db),
):
    _pagination(limit, offset)
    if frm and to and frm > to: raise HTTPException(422, 'from must not exceed to')
    if record_type == 'all':
        # Page a single SQL union before hydrating safe fields. A cycle filter
        # excludes plots (which have no cycle), rather than silently ignoring it.
        branches = []
        for kind, model in MODELS.items():
            if cycle and kind == 'plot':
                continue
            query = _query_records(db, kind, frm, to, owner, plot, cycle)
            branches.append(query.with_only_columns(
                model.id.label('id'), model.created_at.label('created_at'),
                literal(kind).label('type'), maintain_column_froms=True,
            ))
        combined = union_all(*branches).subquery()
        total = int(db.scalar(select(func.count()).select_from(combined)) or 0)
        keys = db.execute(select(combined).order_by(
            combined.c.created_at.desc(), combined.c.type.desc(), combined.c.id.desc(),
        ).limit(limit).offset(offset)).all()
        hydrated, attachments = {}, {}
        for kind, model in MODELS.items():
            ids = [key.id for key in keys if key.type == kind]
            if not ids:
                continue
            hydrated.update({(kind, r.id): r for r in db.scalars(select(model).where(model.id.in_(ids))).all()})
            attachments[kind] = _attachments(db, kind, ids)
        rows = list(hydrated.values())
        users, plots, cycles, transactions = _context(db, rows)
        items = []
        for key in keys:
            row = hydrated[(key.type, key.id)]
            items.append(_row(key.type, row, users.get(row.owner_id),
                _record_plot(plots, cycles, transactions, row),
                _record_cycle(cycles, transactions, row), attachments[key.type].get(key.id, [])))
        return {'type': 'all', 'limit': limit, 'offset': offset, 'total': total, 'items': items}
    query = _query_records(db, record_type, frm, to, owner, plot, cycle)
    model = MODELS[record_type]
    total = db.scalar(select(func.count()).select_from(query.subquery())) or 0
    rows = list(db.scalars(query.order_by(model.created_at.desc(), model.id.desc()).limit(limit).offset(offset)).all())
    users, plots, cycles, transactions = _context(db, rows)
    attachments = _attachments(db, record_type, [r.id for r in rows])
    return {'type': record_type, 'limit': limit, 'offset': offset, 'total': int(total), 'items': [
        _row(record_type, r, users.get(r.owner_id), _record_plot(plots, cycles, transactions, r), _record_cycle(cycles, transactions, r), attachments.get(r.id, [])) for r in rows
    ]}


@router.get('/records/{record_type}/{record_id}')
def get_admin_record(record_type: RecordType, record_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    row = db.scalar(select(MODELS[record_type]).where(MODELS[record_type].id == record_id))
    if row is None: raise HTTPException(404, 'Resource not found')
    users, plots, cycles, transactions = _context(db, [row])
    return _row(record_type, row, users.get(row.owner_id), _record_plot(plots, cycles, transactions, row), _record_cycle(cycles, transactions, row), _attachments(db, record_type, [row.id]).get(row.id, []))


def _target_query(body: AnnouncementCreate, db: Session):
    if body.target_type == 'all':
        if body.user_ids or body.role: raise HTTPException(422, 'all target cannot include userIds or role')
        return select(User.id).where(User.role == 'farmer', User.status == 'active')
    if body.target_type == 'selected':
        if not body.user_ids or body.role: raise HTTPException(422, 'selected target requires userIds')
        found = set(db.scalars(select(User.id).where(User.id.in_(body.user_ids), User.role == 'farmer', User.status == 'active')).all())
        if found != set(body.user_ids): raise HTTPException(422, 'one or more users were not found')
        return select(User.id).where(User.id.in_(body.user_ids), User.status == 'active')
    if not body.role or body.user_ids: raise HTTPException(422, 'role target requires role')
    if body.role != 'farmer': raise HTTPException(422, 'announcements may target farmers only')
    return select(User.id).where(User.role == 'farmer', User.status == 'active')


def _announcement_out(row, count=None):
    return {k: getattr(row, k) for k in ('id', 'owner_id', 'target_type', 'target_role', 'title', 'body', 'status', 'created_at', 'queued_at', 'sent_at', 'cancelled_at')} | {'target_count': count}


@router.post('/announcements/preview')
def preview_announcement(body: AnnouncementCreate, identity=Depends(admin_session), db: Session = Depends(get_db)):
    return {'targetType': body.target_type, 'targetCount': db.scalar(select(func.count()).select_from(_target_query(body, db).subquery())) or 0}


@router.post('/announcements', response_model=AnnouncementOut, status_code=201)
def create_announcement(body: AnnouncementCreate, identity=Depends(admin_session), db: Session = Depends(get_db)):
    _target_query(body, db)
    row = Announcement(owner_id=identity[1].id, target_type=body.target_type, target_role=body.role, target_user_ids=[str(x) for x in body.user_ids] or None,
                       title=body.title, body=body.body)
    db.add(row); db.flush()
    _audit(db, identity[1].id, 'announcement_created', 'announcement', row.id, {'targetType': body.target_type})
    db.commit(); db.refresh(row)
    return _announcement_out(row, db.scalar(select(func.count()).select_from(_target_query(body, db).subquery())))


@router.get('/announcements', response_model=list[AnnouncementOut])
def list_announcements(identity=Depends(admin_session), db: Session = Depends(get_db)):
    rows = db.scalars(select(Announcement).where(Announcement.owner_id == identity[1].id).order_by(Announcement.created_at.desc(), Announcement.id.desc())).all()
    return [_announcement_out(row, db.scalar(select(func.count(AnnouncementRecipient.id)).where(AnnouncementRecipient.announcement_id == row.id))) for row in rows]


def _owned_announcement(announcement_id, owner_id, db):
    row = db.scalar(select(Announcement).where(Announcement.id == announcement_id, Announcement.owner_id == owner_id))
    if row is None: raise HTTPException(404, 'Announcement not found')
    return row


@router.get('/announcements/{announcement_id}', response_model=AnnouncementOut)
def get_announcement(announcement_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    row = _owned_announcement(announcement_id, identity[1].id, db)
    return _announcement_out(row, db.scalar(select(func.count(AnnouncementRecipient.id)).where(AnnouncementRecipient.announcement_id == row.id)))


@router.post('/announcements/{announcement_id}/send', response_model=AnnouncementOut)
def send_announcement(announcement_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    row = db.scalar(select(Announcement).where(Announcement.id == announcement_id, Announcement.owner_id == identity[1].id).with_for_update())
    if row is None: raise HTTPException(404, 'Announcement not found')
    if row.status != 'draft': raise HTTPException(409, 'only drafts can be sent')
    if row.target_type == 'all': user_ids = db.scalars(select(User.id).where(User.role == 'farmer', User.status == 'active')).all()
    elif row.target_type == 'role': user_ids = db.scalars(select(User.id).where(User.role == 'farmer', User.role == row.target_role, User.status == 'active')).all()
    else: user_ids = db.scalars(select(User.id).where(User.id.in_([uuid.UUID(x) for x in (row.target_user_ids or [])]), User.role == 'farmer', User.status == 'active')).all()
    if not user_ids: raise HTTPException(422, 'announcement has no recipients')
    now = datetime.now(timezone.utc)
    row.status, row.queued_at = 'queued', now
    notifications = []
    for user_id in user_ids:
        recipient = AnnouncementRecipient(announcement_id=row.id, user_id=user_id)
        db.add(recipient); db.flush()
        notification = Notification(owner_id=user_id, announcement_id=row.id, kind='admin_announcement', title=row.title, body=row.body)
        db.add(notification); notifications.append(notification)
    db.flush()
    enqueue_push_outbox(db, notifications=notifications, commit=False)
    _audit(db, identity[1].id, 'announcement_sent', 'announcement', row.id, {'recipientCount': len(user_ids)})
    db.commit()
    db.refresh(row)
    return _announcement_out(row, len(user_ids))


@router.post('/announcements/{announcement_id}/cancel', response_model=AnnouncementOut)
def cancel_announcement(announcement_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    row = db.scalar(select(Announcement).where(Announcement.id == announcement_id, Announcement.owner_id == identity[1].id).with_for_update())
    if row is None: raise HTTPException(404, 'Announcement not found')
    if row.status not in ('draft', 'queued', 'sending'): raise HTTPException(409, 'announcement cannot be cancelled')
    row.status, row.cancelled_at = 'cancelled', datetime.now(timezone.utc)
    db.execute(update(AnnouncementRecipient).where(AnnouncementRecipient.announcement_id == row.id, AnnouncementRecipient.status == 'pending').values(status='suppressed'))
    db.execute(update(Notification).where(Notification.announcement_id == row.id, Notification.dismissed_at.is_(None)).values(dismissed_at=row.cancelled_at))
    _audit(db, identity[1].id, 'announcement_cancelled', 'announcement', row.id)
    db.commit(); db.refresh(row)
    return _announcement_out(row, db.scalar(select(func.count(AnnouncementRecipient.id)).where(AnnouncementRecipient.announcement_id == row.id)))


@router.get('/announcements/{announcement_id}/delivery-summary', response_model=AnnouncementSummaryOut)
def announcement_summary(announcement_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    row = _owned_announcement(announcement_id, identity[1].id, db)
    counts = {status: count for status, count in db.execute(select(AnnouncementRecipient.status, func.count()).where(AnnouncementRecipient.announcement_id == row.id).group_by(AnnouncementRecipient.status)).all()}
    return {'announcement_id': row.id, 'status': row.status, 'total': sum(counts.values()), 'pending': counts.get('pending', 0), 'sent': counts.get('sent', 0), 'failed': counts.get('failed', 0), 'suppressed': counts.get('suppressed', 0)}


_SECRET_WORDS = ('password', 'token', 'secret', 'credential', 'p256dh', 'auth', 'push_key')


def _sanitize(value):
    if isinstance(value, dict):
        return {str(k): _sanitize(v) for k, v in value.items() if not any(word in str(k).lower() for word in _SECRET_WORDS)}
    if isinstance(value, (list, tuple)):
        return [_sanitize(v) for v in value]
    if isinstance(value, (uuid.UUID, date, datetime)):
        return str(value)
    return value


def _audit(db, actor_id, action, target_type, target_id=None, metadata=None):
    # Audit rows are committed atomically with the primary admin action.
    db.add(AuditLog(actor_id=actor_id, action=action, target_type=target_type,
                    target_id=target_id, metadata_json=_sanitize(metadata or {})))


def _user_out(user):
    return {'id': user.id, 'email': user.email, 'role': user.role, 'status': user.status,
            'firstName': user.first_name, 'lastName': user.last_name, 'birthDate': user.birth_date,
            'houseNumber': user.house_number, 'subdistrict': user.subdistrict, 'district': user.district,
            'province': user.province, 'phone': user.phone, 'createdAt': user.created_at}


def _guard_admin_count(db, target, new_role=None, new_status=None):
    losing_admin = (
        target.role == 'admin'
        and target.status == 'active'
        and (new_role == 'farmer' or new_status == 'suspended')
    )
    if not losing_admin:
        return

    # Lock every active admin before counting.  This serializes transitions
    # that could otherwise each observe the same last-admin count.
    active_admin_ids = db.scalars(
        select(User.id)
        .where(User.role == 'admin', User.status == 'active')
        .order_by(User.id)
        .with_for_update()
    ).all()
    if len(active_admin_ids) <= 1:
        raise HTTPException(409, 'cannot remove or suspend the last active admin')


@router.get('/users')
def list_admin_users(q: str | None = Query(None, max_length=200), role: Literal['farmer', 'admin'] | None = None,
                    status: Literal['active', 'suspended'] | None = None, limit: int = Query(50), offset: int = Query(0),
                    identity=Depends(admin_session), db: Session = Depends(get_db)):
    _pagination(limit, offset)
    query = select(User)
    if q:
        term = '%' + q.strip().lower() + '%'
        query = query.where(func.lower(User.email).like(term) | func.lower(func.coalesce(User.first_name, '')).like(term) | func.lower(func.coalesce(User.last_name, '')).like(term))
    if role: query = query.where(User.role == role)
    if status: query = query.where(User.status == status)
    total = int(db.scalar(select(func.count()).select_from(query.subquery())) or 0)
    rows = db.scalars(query.order_by(User.created_at.desc(), User.id.desc()).limit(limit).offset(offset)).all()
    return {'limit': limit, 'offset': offset, 'total': total, 'items': [_user_out(u) for u in rows]}


@router.get('/users/{user_id}')
def get_admin_user(user_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if user is None: raise HTTPException(404, 'User not found')
    return _user_out(user)


@router.patch('/users/{user_id}')
def update_admin_user(user_id: uuid.UUID, body: AdminUserPatch, identity=Depends(admin_session), db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if user is None: raise HTTPException(404, 'User not found')
    changes = body.model_dump(exclude_unset=True)
    new_role = changes.get('role', user.role)
    _guard_admin_count(db, user, new_role=new_role, new_status=changes.get('status'))
    for key, value in changes.items(): setattr(user, key, value)
    _audit(db, identity[1].id, 'admin_profile_changed' if 'role' not in changes else 'role_changed', 'user', user.id, {'fields': list(changes), 'role': new_role})
    db.commit(); db.refresh(user)
    return _user_out(user)


@router.post('/users/{user_id}/suspend')
def suspend_admin_user(user_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if user is None: raise HTTPException(404, 'User not found')
    if user.status == 'suspended': return _user_out(user)
    _guard_admin_count(db, user, new_status='suspended')
    user.status = 'suspended'
    revoked_at = datetime.now(timezone.utc)
    revoked = db.query(AuthSession).filter(
        AuthSession.user_id == user.id,
        AuthSession.revoked_at.is_(None),
    ).update({'revoked_at': revoked_at}, synchronize_session=False)
    _audit(db, identity[1].id, 'user_suspended', 'user', user.id, {'sessionsRevoked': revoked})
    db.commit(); db.refresh(user)
    return _user_out(user)


@router.post('/users/{user_id}/activate')
def activate_admin_user(user_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if user is None: raise HTTPException(404, 'User not found')
    if user.status == 'active': return _user_out(user)
    user.status = 'active'
    _audit(db, identity[1].id, 'user_activated', 'user', user.id)
    db.commit(); db.refresh(user)
    return _user_out(user)


@router.post('/users/{user_id}/revoke-sessions')
@router.post('/users/{user_id}/sessions/revoke')
def revoke_admin_user_sessions(user_id: uuid.UUID, identity=Depends(admin_session), db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if user is None: raise HTTPException(404, 'User not found')
    now = datetime.now(timezone.utc)
    count = db.query(AuthSession).filter(AuthSession.user_id == user.id, AuthSession.revoked_at.is_(None)).update({'revoked_at': now})
    _audit(db, identity[1].id, 'sessions_revoked', 'user', user.id, {'count': count})
    db.commit()
    return {'revoked': count}


@router.get('/audit-logs')
def list_audit_logs(action: str | None = Query(None, max_length=64), target_type: str | None = Query(None, max_length=64),
                   actor_id: uuid.UUID | None = None, target_id: uuid.UUID | None = None,
                   limit: int = Query(50), offset: int = Query(0), identity=Depends(admin_session), db: Session = Depends(get_db)):
    _pagination(limit, offset)
    query = select(AuditLog)
    if action: query = query.where(AuditLog.action == action)
    if target_type: query = query.where(AuditLog.target_type == target_type)
    if actor_id: query = query.where(AuditLog.actor_id == actor_id)
    if target_id: query = query.where(AuditLog.target_id == target_id)
    total = int(db.scalar(select(func.count()).select_from(query.subquery())) or 0)
    rows = db.scalars(query.order_by(AuditLog.created_at.desc(), AuditLog.id.desc()).limit(limit).offset(offset)).all()
    return {'limit': limit, 'offset': offset, 'total': total, 'items': [{'id': r.id, 'actorId': r.actor_id, 'action': r.action, 'targetType': r.target_type, 'targetId': r.target_id, 'metadata': r.metadata_json, 'createdAt': r.created_at} for r in rows]}

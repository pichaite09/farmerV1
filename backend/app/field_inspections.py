import uuid
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.main import current_session
from app.models import FieldInspection, Plot, ProductionCycle
from app.schemas import FieldInspectionCreate, FieldInspectionOut, FieldInspectionPatch
from app.follow_up import follow_up_status, sync_follow_up_task

router = APIRouter(prefix='/api/v1')


def user(identity):
    return identity[1]


def not_found():
    raise HTTPException(404, 'Resource not found')


def owned(db, model, owner, item_id):
    row = db.scalar(select(model).where(model.id == item_id, model.owner_id == owner.id))
    if row is None:
        not_found()
    return row


def validate_parent_links(db, owner, plot_id, cycle_id):
    owned(db, Plot, owner, plot_id)
    if cycle_id is not None:
        cycle = owned(db, ProductionCycle, owner, cycle_id)
        if cycle.plot_id != plot_id:
            raise HTTPException(422, 'Cycle must belong to the selected plot')


def out(db, row):
    payload = FieldInspectionOut.model_validate(row).model_dump()
    payload['follow_up_status'] = follow_up_status(db, row)
    return payload


@router.get('/field-inspections', response_model=list[FieldInspectionOut])
def list_field_inspections(
    limit: int = Query(50),
    offset: int = Query(0),
    plot_id: uuid.UUID | None = Query(None, alias='plotId'),
    cycle_id: uuid.UUID | None = Query(None, alias='cycleId'),
    identity=Depends(current_session),
    db: Session = Depends(get_db),
):
    if limit < 1 or limit > 200 or offset < 0:
        raise HTTPException(422, 'Invalid pagination')
    query = select(FieldInspection).where(FieldInspection.owner_id == user(identity).id)
    if plot_id is not None:
        query = query.where(FieldInspection.plot_id == plot_id)
    if cycle_id is not None:
        query = query.where(FieldInspection.cycle_id == cycle_id)
    rows = db.scalars(query.order_by(desc(FieldInspection.inspection_date), desc(FieldInspection.id)).limit(limit).offset(offset)).all()
    return [out(db, row) for row in rows]


@router.post('/field-inspections', status_code=201, response_model=FieldInspectionOut)
def create_field_inspection(body: FieldInspectionCreate, identity=Depends(current_session), db: Session = Depends(get_db)):
    owner = user(identity)
    validate_parent_links(db, owner, body.plot_id, body.cycle_id)
    row = FieldInspection(owner_id=owner.id, **body.model_dump())
    db.add(row)
    sync_follow_up_task(db, row)
    db.commit()
    db.refresh(row)
    return out(db, row)


@router.get('/field-inspections/{item_id}', response_model=FieldInspectionOut)
def get_field_inspection(item_id: uuid.UUID, identity=Depends(current_session), db: Session = Depends(get_db)):
    return out(db, owned(db, FieldInspection, user(identity), item_id))


@router.patch('/field-inspections/{item_id}', response_model=FieldInspectionOut)
def patch_field_inspection(item_id: uuid.UUID, body: FieldInspectionPatch, identity=Depends(current_session), db: Session = Depends(get_db)):
    owner = user(identity)
    row = owned(db, FieldInspection, owner, item_id)
    changes = body.model_dump(exclude_unset=True)
    final_plot_id = changes.get('plot_id', row.plot_id)
    final_cycle_id = changes.get('cycle_id', row.cycle_id)
    validate_parent_links(db, owner, final_plot_id, final_cycle_id)
    for key, value in changes.items():
        setattr(row, key, value)
    sync_follow_up_task(db, row)
    db.commit()
    db.refresh(row)
    return out(db, row)


@router.delete('/field-inspections/{item_id}', status_code=204)
def delete_field_inspection(item_id: uuid.UUID, identity=Depends(current_session), db: Session = Depends(get_db)):
    row = owned(db, FieldInspection, user(identity), item_id)
    db.delete(row)
    db.commit()
    return Response(status_code=204)

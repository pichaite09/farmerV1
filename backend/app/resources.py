import uuid
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import select, desc
from sqlalchemy.orm import Session
from app.database import get_db
from app.main import current_session
from app.models import Plot, ProductionCycle, Activity
from app.schemas import PlotCreate, PlotPatch, PlotOut, CycleCreate, CyclePatch, CycleOut, ActivityCreate, ActivityPatch, ActivityOut

router = APIRouter(prefix='/api/v1')
def identity_user(identity): return identity[1]
def missing(): raise HTTPException(404, 'Resource not found')
def limit_offset(limit: int, offset: int):
    if limit < 1 or limit > 200 or offset < 0: raise HTTPException(422, 'Invalid pagination')
def owned(db, model, ident, item_id):
    item = db.scalar(select(model).where(model.id == item_id, model.owner_id == ident.id))
    if item is None: missing()
    return item

def plot_out(p): return PlotOut.model_validate(p)
def cycle_out(db, c):
    p = db.get(Plot, c.plot_id)
    return CycleOut.model_validate({'id': c.id, 'name': c.name, 'plot_id': c.plot_id, 'plot_name': p.name, 'crop_type': c.crop_type, 'variety': c.variety or '', 'planting_method': c.planting_method, 'start_date': c.start_date, 'status': c.status, 'created_at': c.created_at, 'updated_at': c.updated_at})
def activity_out(a): return ActivityOut.model_validate(a)

@router.get('/plots', response_model=list[PlotOut])
def list_plots(limit: int=Query(50), offset: int=Query(0), identity=Depends(current_session), db: Session=Depends(get_db)):
    u=identity_user(identity); limit_offset(limit,offset)
    return [plot_out(x) for x in db.scalars(select(Plot).where(Plot.owner_id==u.id).order_by(Plot.name, Plot.id).limit(limit).offset(offset))]
@router.post('/plots', status_code=201, response_model=PlotOut)
def create_plot(body: PlotCreate, identity=Depends(current_session), db: Session=Depends(get_db)):
    p=Plot(owner_id=identity_user(identity).id, **body.model_dump(exclude={'image_url'})); db.add(p); db.commit(); db.refresh(p); return plot_out(p)
@router.get('/plots/{item_id}', response_model=PlotOut)
def get_plot(item_id: uuid.UUID, identity=Depends(current_session), db: Session=Depends(get_db)): return plot_out(owned(db,Plot,identity_user(identity),item_id))
@router.patch('/plots/{item_id}', response_model=PlotOut)
def update_plot(item_id: uuid.UUID, body: PlotPatch, identity=Depends(current_session), db: Session=Depends(get_db)):
    p=owned(db,Plot,identity_user(identity),item_id)
    for k,v in body.model_dump(exclude_unset=True, exclude={'image_url'}).items(): setattr(p,k,v)
    db.commit(); db.refresh(p); return plot_out(p)
@router.delete('/plots/{item_id}', status_code=204)
def delete_plot(item_id: uuid.UUID, identity=Depends(current_session), db: Session=Depends(get_db)):
    p=owned(db,Plot,identity_user(identity),item_id)
    if db.scalar(select(ProductionCycle.id).where(ProductionCycle.plot_id==p.id)): raise HTTPException(409,'Plot has production cycles')
    db.delete(p); db.commit(); return Response(status_code=204)

@router.get('/cycles', response_model=list[CycleOut])
def list_cycles(limit: int=Query(50), offset: int=Query(0), identity=Depends(current_session), db: Session=Depends(get_db)):
    u=identity_user(identity); limit_offset(limit,offset)
    rows=db.scalars(select(ProductionCycle).where(ProductionCycle.owner_id==u.id).order_by(desc(ProductionCycle.start_date),desc(ProductionCycle.id)).limit(limit).offset(offset)).all()
    return [cycle_out(db,x) for x in rows]
@router.post('/cycles', status_code=201, response_model=CycleOut)
def create_cycle(body: CycleCreate, identity=Depends(current_session), db: Session=Depends(get_db)):
    u=identity_user(identity); p=owned(db,Plot,u,body.plot_id)
    c=ProductionCycle(owner_id=u.id, **body.model_dump()); db.add(c); db.commit(); db.refresh(c); return cycle_out(db,c)
@router.get('/cycles/{item_id}', response_model=CycleOut)
def get_cycle(item_id: uuid.UUID, identity=Depends(current_session), db: Session=Depends(get_db)): return cycle_out(db,owned(db,ProductionCycle,identity_user(identity),item_id))
@router.patch('/cycles/{item_id}', response_model=CycleOut)
def update_cycle(item_id: uuid.UUID, body: CyclePatch, identity=Depends(current_session), db: Session=Depends(get_db)):
    c=owned(db,ProductionCycle,identity_user(identity),item_id); changes=body.model_dump(exclude_unset=True)
    if 'plot_id' in changes: owned(db,Plot,identity_user(identity),changes['plot_id'])
    for k,v in changes.items(): setattr(c,k,v)
    db.commit(); db.refresh(c); return cycle_out(db,c)
@router.delete('/cycles/{item_id}', status_code=204)
def delete_cycle(item_id: uuid.UUID, identity=Depends(current_session), db: Session=Depends(get_db)):
    c=owned(db,ProductionCycle,identity_user(identity),item_id)
    if db.scalar(select(Activity.id).where(Activity.cycle_id==c.id)): raise HTTPException(409,'Cycle has activities')
    db.delete(c); db.commit(); return Response(status_code=204)

@router.get('/activities', response_model=list[ActivityOut])
def list_activities(limit: int=Query(50), offset: int=Query(0), cycle_id: uuid.UUID|None=None, identity=Depends(current_session), db: Session=Depends(get_db)):
    u=identity_user(identity); limit_offset(limit,offset); q=select(Activity).where(Activity.owner_id==u.id)
    if cycle_id is not None: q=q.where(Activity.cycle_id==cycle_id)
    return [activity_out(x) for x in db.scalars(q.order_by(desc(Activity.date),desc(Activity.id)).limit(limit).offset(offset))]
@router.post('/activities', status_code=201, response_model=ActivityOut)
def create_activity(body: ActivityCreate, identity=Depends(current_session), db: Session=Depends(get_db)):
    u=identity_user(identity); c=owned(db,ProductionCycle,u,body.cycle_id)
    if c.status=='completed' and not body.complete_cycle: raise HTTPException(409,'Cycle is completed')
    a=Activity(owner_id=u.id, **body.model_dump(exclude={'complete_cycle','image_url'})); db.add(a)
    if body.complete_cycle: c.status='completed'
    db.commit(); db.refresh(a); return activity_out(a)
@router.get('/activities/{item_id}', response_model=ActivityOut)
def get_activity(item_id: uuid.UUID, identity=Depends(current_session), db: Session=Depends(get_db)): return activity_out(owned(db,Activity,identity_user(identity),item_id))
@router.patch('/activities/{item_id}', response_model=ActivityOut)
def update_activity(item_id: uuid.UUID, body: ActivityPatch, identity=Depends(current_session), db: Session=Depends(get_db)):
    a=owned(db,Activity,identity_user(identity),item_id); c=owned(db,ProductionCycle,identity_user(identity),a.cycle_id)
    if c.status=='completed': raise HTTPException(409,'Cycle is completed')
    changes=body.model_dump(exclude_unset=True, exclude={'image_url'})
    if 'cycle_id' in changes: owned(db,ProductionCycle,identity_user(identity),changes['cycle_id'])
    for k,v in changes.items(): setattr(a,k,v)
    db.commit(); db.refresh(a); return activity_out(a)
@router.delete('/activities/{item_id}', status_code=204)
def delete_activity(item_id: uuid.UUID, identity=Depends(current_session), db: Session=Depends(get_db)):
    a=owned(db,Activity,identity_user(identity),item_id); c=owned(db,ProductionCycle,identity_user(identity),a.cycle_id)
    if c.status=='completed': raise HTTPException(409,'Cycle is completed')
    db.delete(a); db.commit(); return Response(status_code=204)

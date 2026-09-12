import uuid
from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from app.database import get_db
from app.main import farmer_session
from app.models import FcmDeviceToken
from app.schemas import FcmDeviceTokenCreate, FcmDeviceTokenOut

router = APIRouter(prefix='/api/v1/devices', tags=['devices'])

@router.post('/push-token', status_code=201, response_model=FcmDeviceTokenOut)
def register_push_token(body: FcmDeviceTokenCreate, identity=Depends(farmer_session), db: Session = Depends(get_db)):
    owner_id = identity[1].id
    existing = db.scalar(select(FcmDeviceToken).where(FcmDeviceToken.token == body.token))
    if existing is not None and existing.owner_id != owner_id:
        raise HTTPException(409, 'Device token already registered')
    if existing is None:
        existing = FcmDeviceToken(owner_id=owner_id, token=body.token)
        db.add(existing)
    else:
        existing.active = True
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, 'Device token already registered')
    db.refresh(existing)
    return existing

@router.delete('/push-token', status_code=204)
def deactivate_push_token(body: FcmDeviceTokenCreate, identity=Depends(farmer_session), db: Session = Depends(get_db)):
    device = db.scalar(select(FcmDeviceToken).where(FcmDeviceToken.token == body.token, FcmDeviceToken.owner_id == identity[1].id))
    if device is None:
        raise HTTPException(404, 'Device token not found')
    device.active = False
    db.commit()
    return Response(status_code=204)

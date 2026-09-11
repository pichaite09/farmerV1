from __future__ import annotations

import os
import uuid
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db, settings
from app.main import farmer_session
from app.models import Activity, Attachment, FieldInspection, Plot, ProductionCycle, Task

router = APIRouter(prefix='/api/v1')
MAX_SIZE = 10 * 1024 * 1024
ALLOWED = {
    '.jpg': ('image/jpeg', b'jpeg'),
    '.jpeg': ('image/jpeg', b'jpeg'),
    '.png': ('image/png', b'png'),
    '.webp': ('image/webp', b'webp'),
}


class AttachmentOut(BaseModel):
    model_config = ConfigDict(alias_generator=lambda s: ''.join([s.split('_')[0]] + [p.title() for p in s.split('_')[1:]]), populate_by_name=True, from_attributes=True)
    id: uuid.UUID
    parent_type: str
    parent_id: uuid.UUID
    content_type: str
    size_bytes: int
    created_at: datetime
    content_url: str


def _user(identity):
    return identity[1]


def _not_found():
    raise HTTPException(404, 'Resource not found')


def _storage_dir() -> Path:
    path = Path(settings.attachment_storage_path).resolve()
    path.mkdir(parents=True, exist_ok=True)
    return path


def _signature_kind(header: bytes) -> bytes | None:
    if header.startswith(b'\xff\xd8\xff'):
        return b'jpeg'
    if header.startswith(b'\x89PNG\r\n\x1a\n'):
        return b'png'
    if len(header) >= 12 and header[:4] == b'RIFF' and header[8:12] == b'WEBP':
        return b'webp'
    return None


def _parent(db: Session, parent_type: str, parent_id: uuid.UUID, user_id: uuid.UUID):
    if parent_type == 'plot':
        parent = db.scalar(select(Plot).where(Plot.id == parent_id, Plot.owner_id == user_id))
    elif parent_type == 'activity':
        parent = db.scalar(
            select(Activity)
            .join(ProductionCycle, Activity.cycle_id == ProductionCycle.id)
            .where(Activity.id == parent_id, Activity.owner_id == user_id, ProductionCycle.owner_id == user_id)
        )
    elif parent_type == 'field_inspection':
        parent = db.scalar(select(FieldInspection).where(FieldInspection.id == parent_id, FieldInspection.owner_id == user_id))
    elif parent_type == 'task':
        parent = db.scalar(select(Task).where(Task.id == parent_id, Task.owner_id == user_id))
    else:
        raise HTTPException(422, 'parentType must be plot, activity, field_inspection, or task')
    if parent is None:
        _not_found()
    return parent


def _content_url(attachment_id: uuid.UUID) -> str:
    return f'/api/v1/attachments/{attachment_id}/content'


def _out(row: Attachment) -> AttachmentOut:
    return AttachmentOut.model_validate({
        'id': row.id,
        'parent_type': row.parent_type,
        'parent_id': row.parent_id,
        'content_type': row.content_type,
        'size_bytes': row.size_bytes,
        'created_at': row.created_at,
        'content_url': _content_url(row.id),
    })


@router.post('/attachments', status_code=201, response_model=AttachmentOut)
def upload_attachment(
    parent_type: str = Form(..., alias='parentType'),
    parent_id: uuid.UUID = Form(..., alias='parentId'),
    file: UploadFile = File(...),
    idempotency_key: str | None = Header(None, alias='Idempotency-Key', max_length=255),
    identity=Depends(farmer_session),
    db: Session = Depends(get_db),
):
    # Fixed multipart fields; filenames are never used as storage identifiers.
    parent_type = parent_type.strip().lower()
    user_id = _user(identity).id
    parent = _parent(db, parent_type, parent_id, user_id)
    if idempotency_key:
        existing_for_key = db.scalar(select(Attachment).where(
            Attachment.owner_id == user_id,
            Attachment.idempotency_key == idempotency_key,
        ))
        if existing_for_key is not None:
            if existing_for_key.parent_type != parent_type or existing_for_key.parent_id != parent_id:
                raise HTTPException(409, 'Idempotency-Key already used for a different attachment request')
            return _out(existing_for_key)
    filename = Path(file.filename or '').name
    suffix = Path(filename).suffix.lower()
    expected = ALLOWED.get(suffix)
    if expected is None:
        raise HTTPException(415, 'Unsupported image extension')

    storage_dir = _storage_dir()
    temp_path = storage_dir / f'.{uuid.uuid4().hex}.upload'
    final_path: Path | None = None
    total = 0
    prefix = b''
    try:
        with temp_path.open('wb') as output:
            while True:
                chunk = file.file.read(1024 * 1024)
                if not chunk:
                    break
                if total == 0:
                    prefix = chunk[:32]
                total += len(chunk)
                if total > MAX_SIZE:
                    raise HTTPException(413, 'Image exceeds 10 MiB limit')
                output.write(chunk)
        kind = _signature_kind(prefix)
        if kind != expected[1]:
            raise HTTPException(415, 'Image signature does not match extension')
        content_type = expected[0]
        storage_name = f'{uuid.uuid4().hex}{suffix}'
        final_path = storage_dir / storage_name
        os.replace(temp_path, final_path)

        old_storage_name = None
        existing = None
        if parent_type in ('plot', 'activity'):
            existing = db.scalar(select(Attachment).where(
                Attachment.owner_id == user_id,
                Attachment.parent_type == parent_type,
                Attachment.parent_id == parent_id,
            ))
        if existing is None:
            existing = Attachment(owner_id=user_id, parent_type=parent_type, parent_id=parent_id)
            db.add(existing)
        else:
            old_storage_name = existing.storage_name
        existing.storage_name = storage_name
        existing.content_type = content_type
        existing.size_bytes = total
        existing.idempotency_key = idempotency_key
        db.flush()
        if hasattr(parent, 'image_url'):
            parent.image_url = _content_url(existing.id)
        db.commit()
        db.refresh(existing)
        if old_storage_name:
            (storage_dir / old_storage_name).unlink(missing_ok=True)
        return _out(existing)
    except HTTPException:
        temp_path.unlink(missing_ok=True)
        raise
    except IntegrityError:
        db.rollback()
        if idempotency_key:
            raced = db.scalar(select(Attachment).where(
                Attachment.owner_id == user_id,
                Attachment.idempotency_key == idempotency_key,
            ))
            if raced is not None and raced.parent_type == parent_type and raced.parent_id == parent_id:
                if final_path is not None:
                    final_path.unlink(missing_ok=True)
                return _out(raced)
        temp_path.unlink(missing_ok=True)
        if final_path is not None:
            final_path.unlink(missing_ok=True)
        raise
    except Exception:
        db.rollback()
        temp_path.unlink(missing_ok=True)
        if final_path is not None:
            final_path.unlink(missing_ok=True)
        raise
    finally:
        file.file.close()


@router.get('/attachments', response_model=list[AttachmentOut])
def list_attachments(
    parent_type: str = Query(..., alias='parentType'),
    parent_id: uuid.UUID = Query(..., alias='parentId'),
    identity=Depends(farmer_session),
    db: Session = Depends(get_db),
):
    parent_type = parent_type.strip().lower()
    _parent(db, parent_type, parent_id, _user(identity).id)
    rows = db.scalars(select(Attachment).where(Attachment.owner_id == _user(identity).id, Attachment.parent_type == parent_type, Attachment.parent_id == parent_id)).all()
    return [_out(row) for row in rows]


@router.get('/attachments/{attachment_id}/content')
def attachment_content(attachment_id: uuid.UUID, identity=Depends(farmer_session), db: Session = Depends(get_db)):
    row = db.scalar(select(Attachment).where(Attachment.id == attachment_id, Attachment.owner_id == _user(identity).id))
    if row is None:
        _not_found()
    path = _storage_dir() / row.storage_name
    if not path.is_file():
        raise HTTPException(404, 'Attachment content not found')
    return FileResponse(path, media_type=row.content_type)


@router.delete('/attachments/{attachment_id}', status_code=204)
def delete_attachment(attachment_id: uuid.UUID, identity=Depends(farmer_session), db: Session = Depends(get_db)):
    row = db.scalar(select(Attachment).where(Attachment.id == attachment_id, Attachment.owner_id == _user(identity).id))
    if row is None:
        _not_found()
    path = _storage_dir() / row.storage_name
    parent = _parent(db, row.parent_type, row.parent_id, _user(identity).id)
    if hasattr(parent, 'image_url') and parent.image_url == _content_url(row.id):
        parent.image_url = None
    db.delete(row)
    db.commit()
    path.unlink(missing_ok=True)

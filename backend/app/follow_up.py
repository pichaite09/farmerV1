from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import FieldInspection, Task


def sync_follow_up_task(db: Session, inspection: FieldInspection) -> None:
    """Create, update, or remove the single task owned by an inspection."""
    task = None
    if inspection.follow_up_task_id is not None:
        task = db.scalar(
            select(Task).where(
                Task.id == inspection.follow_up_task_id,
                Task.owner_id == inspection.owner_id,
            )
        )

    if not inspection.follow_up_required or inspection.follow_up_date is None or inspection.cycle_id is None:
        if task is not None:
            db.delete(task)
        inspection.follow_up_task_id = None
        return

    task_name = (inspection.notes or '').strip() or 'ติดตามผลการตรวจแปลง'
    if task is None:
        task = Task(
            owner_id=inspection.owner_id,
            name=task_name,
            cycle_id=inspection.cycle_id,
            due_date=inspection.follow_up_date,
            status='pending',
            description=inspection.recommendation,
        )
        db.add(task)
        db.flush()
        inspection.follow_up_task_id = task.id
    else:
        task.name = task_name
        task.cycle_id = inspection.cycle_id
        task.due_date = inspection.follow_up_date
        task.description = inspection.recommendation


def follow_up_status(db: Session, inspection: FieldInspection) -> str | None:
    if inspection.follow_up_task_id is None:
        return None
    task = db.scalar(
        select(Task.status).where(
            Task.id == inspection.follow_up_task_id,
            Task.owner_id == inspection.owner_id,
        )
    )
    return task

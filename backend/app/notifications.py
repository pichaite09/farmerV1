"""In-app reminders for tasks that are due tomorrow."""
from datetime import date, datetime, timedelta, timezone
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.database import get_db
from app.main import current_session
from app.models import Notification, Task, ProductionCycle, Plot
from app.schemas import NotificationOut

router = APIRouter(prefix='/api/v1')


def generate_daily_reminders(
    db: Session,
    today: date | None = None,
    owner_id: uuid.UUID | None = None,
) -> list[Notification]:
    """Create one reminder per eligible owner/task/date and return those reminders.

    The unique constraint on Notification makes repeated and concurrent runs safe.
    """
    run_date = today or date.today()
    tomorrow = run_date + timedelta(days=1)
    task_query = select(Task).where(
        Task.due_date == tomorrow,
        Task.status.notin_(['completed', 'cancelled']),
    )
    if owner_id is not None:
        task_query = task_query.where(Task.owner_id == owner_id)
    tasks = db.scalars(task_query).all()
    for task in tasks:
        statement = insert(Notification).values(
            owner_id=task.owner_id,
            task_id=task.id,
            due_date=task.due_date,
            kind='task_due_tomorrow',
            title='Task due tomorrow',
            body=task.name,
        ).on_conflict_do_nothing(
            index_elements=['owner_id', 'task_id', 'due_date']
        )
        db.execute(statement)
    db.commit()

    notification_query = (
        select(Notification)
        .join(Task, Task.id == Notification.task_id)
        .where(
            Notification.due_date == tomorrow,
            Notification.kind == 'task_due_tomorrow',
            Task.status.notin_(['completed', 'cancelled']),
        )
    )
    if owner_id is not None:
        notification_query = notification_query.where(Notification.owner_id == owner_id)
    return db.scalars(notification_query.order_by(Notification.created_at, Notification.id)).all()


@router.get('/notifications', response_model=list[NotificationOut])
def list_notifications(
    identity=Depends(current_session),
    db: Session = Depends(get_db),
):
    owner_id = identity[1].id
    generate_daily_reminders(db, owner_id=owner_id)
    rows = db.execute(
        select(Notification, Task.name, ProductionCycle.name, Plot.name)
        .join(Task, Task.id == Notification.task_id)
        .join(ProductionCycle, ProductionCycle.id == Task.cycle_id)
        .join(Plot, Plot.id == ProductionCycle.plot_id)
        .where(Notification.owner_id == owner_id, Notification.dismissed_at.is_(None))
        .order_by(Notification.created_at.desc(), Notification.id.desc())
    ).all()
    return [
        {
            'id': notification.id,
            'task_id': notification.task_id,
            'task_name': task_name,
            'cycle_name': cycle_name,
            'plot_name': plot_name,
            'due_date': notification.due_date,
            'kind': notification.kind,
            'title': notification.title,
            'body': notification.body,
            'created_at': notification.created_at,
            'read_at': notification.read_at,
        }
        for notification, task_name, cycle_name, plot_name in rows
    ]


@router.patch('/notifications/{notification_id}/read', response_model=NotificationOut)
def mark_notification_read(
    notification_id: uuid.UUID,
    identity=Depends(current_session),
    db: Session = Depends(get_db),
):
    notification = db.scalar(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.owner_id == identity[1].id,
        )
    )
    if notification is None:
        raise HTTPException(404, 'Notification not found')
    if notification.read_at is None:
        notification.read_at = datetime.now(timezone.utc)
        db.commit()
    return next(
        item for item in list_notifications(identity=identity, db=db)
        if item['id'] == notification_id
    )


@router.delete('/notifications/read', status_code=204)
def clear_read_notifications(
    identity=Depends(current_session),
    db: Session = Depends(get_db),
):
    db.execute(
        update(Notification)
        .where(
            Notification.owner_id == identity[1].id,
            Notification.read_at.is_not(None),
            Notification.dismissed_at.is_(None),
        )
        .values(dismissed_at=datetime.now(timezone.utc))
    )
    db.commit()
    return None

"""Allow cancelled tasks."""
from alembic import op
import sqlalchemy as sa

revision = '0016_cancelled_task_status'
down_revision = '0015_push_outbox'
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint('tasks_status_valid', 'tasks', type_='check')
    op.create_check_constraint(
        'tasks_status_valid', 'tasks',
        "status IN ('pending', 'in_progress', 'completed', 'cancelled')",
    )


def downgrade():
    bind = op.get_bind()
    if bind.execute(sa.text("SELECT EXISTS (SELECT 1 FROM tasks WHERE status = 'cancelled')")).scalar():
        raise RuntimeError('cannot downgrade while cancelled tasks exist')
    op.drop_constraint('tasks_status_valid', 'tasks', type_='check')
    op.create_check_constraint(
        'tasks_status_valid', 'tasks',
        "status IN ('pending', 'in_progress', 'completed')",
    )
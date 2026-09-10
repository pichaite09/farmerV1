"""Add in-app task reminders."""
from alembic import op
import sqlalchemy as sa

revision = '0006_notifications'
down_revision = '0005_cycle_variety'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'notifications',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('task_id', sa.Uuid(), sa.ForeignKey('tasks.id', ondelete='CASCADE'), nullable=False),
        sa.Column('due_date', sa.Date(), nullable=False),
        sa.Column('kind', sa.String(64), nullable=False),
        sa.Column('title', sa.String(200), nullable=False),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('read_at', sa.DateTime(timezone=True)),
        sa.UniqueConstraint('owner_id', 'task_id', 'due_date', name='uq_notification_owner_task_due_date'),
    )
    op.create_index('ix_notifications_owner_id', 'notifications', ['owner_id'])
    op.create_index('ix_notifications_task_id', 'notifications', ['task_id'])


def downgrade():
    op.drop_index('ix_notifications_task_id')
    op.drop_index('ix_notifications_owner_id')
    op.drop_table('notifications')

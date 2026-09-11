"""Add durable admin announcements and recipient-scoped notifications."""
from alembic import op
import sqlalchemy as sa

revision = '0018_admin_announcements'
down_revision = '0017_admin_role'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table('announcements',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('target_type', sa.String(16), nullable=False),
        sa.Column('target_role', sa.String(16)),
        sa.Column('target_user_ids', sa.JSON()),
        sa.Column('title', sa.String(200), nullable=False), sa.Column('body', sa.Text(), nullable=False),
        sa.Column('status', sa.String(16), server_default='draft', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('queued_at', sa.DateTime(timezone=True)), sa.Column('sent_at', sa.DateTime(timezone=True)),
        sa.Column('cancelled_at', sa.DateTime(timezone=True)),
        sa.CheckConstraint("status IN ('draft','queued','sending','sent','cancelled')", name='ck_announcements_status'))
    op.create_index('ix_announcements_owner_id', 'announcements', ['owner_id'])
    op.create_index('ix_announcements_status', 'announcements', ['status'])
    op.create_table('announcement_recipients',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('announcement_id', sa.Uuid(), sa.ForeignKey('announcements.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('status', sa.String(16), server_default='pending', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('announcement_id', 'user_id', name='uq_announcement_recipient'),
        sa.CheckConstraint("status IN ('pending','sent','failed','suppressed')", name='ck_announcement_recipient_status'))
    op.create_index('ix_announcement_recipients_announcement_id', 'announcement_recipients', ['announcement_id'])
    op.create_index('ix_announcement_recipients_user_id', 'announcement_recipients', ['user_id'])
    op.alter_column('notifications', 'task_id', nullable=True)
    op.alter_column('notifications', 'due_date', nullable=True)
    op.add_column('notifications', sa.Column('announcement_id', sa.Uuid(), sa.ForeignKey('announcements.id', ondelete='CASCADE')))
    op.create_index('ix_notifications_announcement_id', 'notifications', ['announcement_id'])

def downgrade():
    bind = op.get_bind()
    # Remove dependent rows first; otherwise restoring legacy NOT NULL columns
    # either fails opaquely or leaves announcement data behind.
    bind.execute(sa.text("DELETE FROM notifications WHERE announcement_id IS NOT NULL"))
    bind.execute(sa.text("DELETE FROM announcement_recipients"))
    bind.execute(sa.text("DELETE FROM announcements"))
    remaining = bind.execute(sa.text(
        "SELECT count(*) FROM notifications WHERE task_id IS NULL OR due_date IS NULL"
    )).scalar_one()
    if remaining:
        raise RuntimeError(
            'cannot downgrade 0018: notifications still contain NULL task_id/due_date'
        )
    op.drop_index('ix_notifications_announcement_id', table_name='notifications')
    op.drop_constraint('notifications_announcement_id_fkey', 'notifications', type_='foreignkey')
    op.drop_column('notifications', 'announcement_id')
    op.alter_column('notifications', 'due_date', nullable=False)
    op.alter_column('notifications', 'task_id', nullable=False)
    op.drop_table('announcement_recipients'); op.drop_index('ix_announcements_status', table_name='announcements'); op.drop_index('ix_announcements_owner_id', table_name='announcements'); op.drop_table('announcements')
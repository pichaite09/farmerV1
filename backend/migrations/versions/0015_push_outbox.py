"""Add durable per-subscription push delivery outbox."""
from alembic import op
import sqlalchemy as sa

revision = '0015_push_outbox'
down_revision = '0014_attachment_idempotency'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'push_outbox',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('notification_id', sa.Uuid(), sa.ForeignKey('notifications.id', ondelete='CASCADE'), nullable=False),
        sa.Column('subscription_id', sa.Uuid(), sa.ForeignKey('push_subscriptions.id', ondelete='CASCADE'), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column('status', sa.String(16), nullable=False, server_default='pending'),
        sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('next_attempt_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('claimed_at', sa.DateTime(timezone=True)),
        sa.Column('sent_at', sa.DateTime(timezone=True)),
        sa.Column('last_error', sa.Text()),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("status IN ('pending', 'claimed', 'sent', 'failed')", name='ck_push_outbox_status'),
        sa.UniqueConstraint('notification_id', 'subscription_id', name='uq_push_outbox_notification_subscription'),
    )
    op.create_index('ix_push_outbox_owner_id', 'push_outbox', ['owner_id'])
    op.create_index('ix_push_outbox_notification_id', 'push_outbox', ['notification_id'])
    op.create_index('ix_push_outbox_subscription_id', 'push_outbox', ['subscription_id'])
    op.create_index('ix_push_outbox_status', 'push_outbox', ['status'])
    op.create_index('ix_push_outbox_next_attempt_at', 'push_outbox', ['next_attempt_at'])


def downgrade():
    for name in ('ix_push_outbox_next_attempt_at', 'ix_push_outbox_status', 'ix_push_outbox_subscription_id', 'ix_push_outbox_notification_id', 'ix_push_outbox_owner_id'):
        op.drop_index(name)
    op.drop_table('push_outbox')

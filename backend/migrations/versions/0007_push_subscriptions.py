"""Store owner-scoped Web Push subscriptions."""
from alembic import op
import sqlalchemy as sa

revision = '0007_push_subscriptions'
down_revision = '0006_notifications'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'push_subscriptions',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('endpoint', sa.String(2048), nullable=False, unique=True),
        sa.Column('p256dh', sa.String(512), nullable=False),
        sa.Column('auth', sa.String(512), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_push_subscriptions_owner_id', 'push_subscriptions', ['owner_id'])


def downgrade():
    op.drop_index('ix_push_subscriptions_owner_id')
    op.drop_table('push_subscriptions')

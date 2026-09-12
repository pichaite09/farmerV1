"""Add owner-scoped Firebase device tokens and FCM outbox targets."""
from alembic import op
import sqlalchemy as sa

revision = '0022_fcm_device_tokens'
down_revision = '0021_announcement_completed'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'fcm_device_tokens',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('token', sa.String(4096), nullable=False),
        sa.Column('active', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('token', name='uq_fcm_device_tokens_token'),
    )
    op.create_index('ix_fcm_device_tokens_owner_id', 'fcm_device_tokens', ['owner_id'])
    op.create_index('ix_fcm_device_tokens_active', 'fcm_device_tokens', ['active'])
    op.add_column('push_outbox', sa.Column('fcm_device_id', sa.Uuid(), sa.ForeignKey('fcm_device_tokens.id', ondelete='CASCADE')))
    op.create_index('ix_push_outbox_fcm_device_id', 'push_outbox', ['fcm_device_id'])
    op.create_unique_constraint('uq_push_outbox_notification_fcm_device', 'push_outbox', ['notification_id', 'fcm_device_id'])
    op.alter_column('push_outbox', 'subscription_id', nullable=True)


def downgrade():
    op.drop_constraint('uq_push_outbox_notification_fcm_device', 'push_outbox', type_='unique')
    op.drop_index('ix_push_outbox_fcm_device_id', table_name='push_outbox')
    op.drop_column('push_outbox', 'fcm_device_id')
    op.alter_column('push_outbox', 'subscription_id', nullable=False)
    op.drop_index('ix_fcm_device_tokens_active', table_name='fcm_device_tokens')
    op.drop_index('ix_fcm_device_tokens_owner_id', table_name='fcm_device_tokens')
    op.drop_table('fcm_device_tokens')

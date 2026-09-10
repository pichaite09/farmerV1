"""Allow users to clear read notifications without losing history."""
from alembic import op
import sqlalchemy as sa

revision = '0008_notification_dismissed'
down_revision = '0007_push_subscriptions'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        'notifications',
        sa.Column('dismissed_at', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade():
    op.drop_column('notifications', 'dismissed_at')

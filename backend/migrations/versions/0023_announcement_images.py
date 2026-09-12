"""Add private announcement image metadata."""
from alembic import op
import sqlalchemy as sa

revision = '0023_announcement_images'
down_revision = '0022_fcm_device_tokens'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('announcements', sa.Column('announcement_type', sa.String(32), nullable=False, server_default='info'))
    op.add_column('announcements', sa.Column('image_attachment_id', sa.Uuid(), sa.ForeignKey('attachments.id', ondelete='SET NULL')))
    op.create_index('ix_announcements_image_attachment_id', 'announcements', ['image_attachment_id'])


def downgrade():
    op.drop_index('ix_announcements_image_attachment_id', table_name='announcements')
    op.drop_column('announcements', 'image_attachment_id')
    op.drop_column('announcements', 'announcement_type')

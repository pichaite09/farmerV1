"""Phase 5 image attachments."""
from alembic import op
import sqlalchemy as sa

revision = '0004_attachments'
down_revision = '0003_phase3'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'attachments',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('parent_type', sa.String(16), nullable=False),
        sa.Column('parent_id', sa.Uuid(), nullable=False),
        sa.Column('storage_name', sa.String(100), nullable=False, unique=True),
        sa.Column('content_type', sa.String(32), nullable=False),
        sa.Column('size_bytes', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("parent_type IN ('plot', 'activity')", name='attachments_parent_type_valid'),
        sa.CheckConstraint('size_bytes > 0 AND size_bytes <= 10485760', name='attachments_size_valid'),
        sa.UniqueConstraint('parent_type', 'parent_id', name='uq_attachment_parent'),
    )
    op.create_index('ix_attachments_owner_id', 'attachments', ['owner_id'])
    op.create_index('ix_attachments_parent', 'attachments', ['parent_type', 'parent_id'])


def downgrade():
    op.drop_index('ix_attachments_parent', table_name='attachments')
    op.drop_index('ix_attachments_owner_id', table_name='attachments')
    op.drop_table('attachments')

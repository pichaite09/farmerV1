"""Add owner-scoped attachment idempotency keys."""
from alembic import op
import sqlalchemy as sa

revision = '0014_attachment_idempotency'
down_revision = '0013_task_attachments'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('attachments', sa.Column('idempotency_key', sa.String(255), nullable=True))
    op.create_unique_constraint(
        'uq_attachment_owner_idempotency_key',
        'attachments',
        ['owner_id', 'idempotency_key'],
    )


def downgrade():
    op.drop_constraint('uq_attachment_owner_idempotency_key', 'attachments', type_='unique')
    op.drop_column('attachments', 'idempotency_key')
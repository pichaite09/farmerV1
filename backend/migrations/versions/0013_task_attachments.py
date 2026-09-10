"""Allow attachments on tasks."""
from alembic import op

revision = '0013_task_attachments'
down_revision = '0012_inspection_follow_up_tasks'
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint('attachments_parent_type_valid', 'attachments', type_='check')
    op.create_check_constraint(
        'attachments_parent_type_valid',
        'attachments',
        "parent_type IN ('plot', 'activity', 'field_inspection', 'task')",
    )


def downgrade():
    op.drop_constraint('attachments_parent_type_valid', 'attachments', type_='check')
    op.create_check_constraint(
        'attachments_parent_type_valid',
        'attachments',
        "parent_type IN ('plot', 'activity', 'field_inspection')",
    )

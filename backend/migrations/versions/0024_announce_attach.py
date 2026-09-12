"""Allow private announcement images in attachments."""
from alembic import op

revision = '0024_announce_attach'
down_revision = '0023_announcement_images'
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint('attachments_parent_type_valid', 'attachments', type_='check')
    op.create_check_constraint(
        'attachments_parent_type_valid',
        'attachments',
        "parent_type IN ('plot', 'activity', 'task', 'field_inspection', 'announcement')",
    )


def downgrade():
    op.drop_constraint('attachments_parent_type_valid', 'attachments', type_='check')
    op.create_check_constraint(
        'attachments_parent_type_valid',
        'attachments',
        "parent_type IN ('plot', 'activity', 'task', 'field_inspection')",
    )

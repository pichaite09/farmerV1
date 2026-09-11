"""Add an explicit terminal status for announcements with no successful push."""
from alembic import op
import sqlalchemy as sa

revision = '0021_announcement_completed'
down_revision = '0020_audit_immutability'
branch_labels = None
depends_on = None

_STATUS_CHECK = "status IN ('draft','queued','sending','sent','completed','cancelled')"
_LEGACY_STATUS_CHECK = "status IN ('draft','queued','sending','sent','cancelled')"


def upgrade():
    # Drop/recreate by name so a partially-applied migration can be retried.
    op.execute(sa.text('ALTER TABLE announcements DROP CONSTRAINT IF EXISTS ck_announcements_status'))
    op.create_check_constraint('ck_announcements_status', 'announcements', _STATUS_CHECK)


def downgrade():
    bind = op.get_bind()
    bind.execute(sa.text("UPDATE announcements SET status = 'sent' WHERE status = 'completed'"))
    bind.execute(sa.text('ALTER TABLE announcements DROP CONSTRAINT IF EXISTS ck_announcements_status'))
    op.create_check_constraint('ck_announcements_status', 'announcements', _LEGACY_STATUS_CHECK)

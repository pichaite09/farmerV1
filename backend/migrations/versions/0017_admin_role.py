"""Allow the explicitly provisioned admin role."""
from alembic import op
import sqlalchemy as sa

revision = '0017_admin_role'
down_revision = '0016_cancelled_task_status'
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint('users_farmer_only', 'users', type_='check')
    op.create_check_constraint(
        'users_role_valid', 'users', "role IN ('farmer', 'admin')"
    )


def downgrade():
    bind = op.get_bind()
    if bind.execute(sa.text("SELECT EXISTS (SELECT 1 FROM users WHERE role = 'admin')")).scalar():
        raise RuntimeError('cannot downgrade while admin users exist')
    op.drop_constraint('users_role_valid', 'users', type_='check')
    op.create_check_constraint('users_farmer_only', 'users', "role = 'farmer'")

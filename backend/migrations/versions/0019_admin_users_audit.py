"""Add user lifecycle state and immutable admin audit records."""
from alembic import op
import sqlalchemy as sa

revision = '0019_admin_users_audit'
down_revision = '0018_admin_announcements'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('users', sa.Column('status', sa.String(16), server_default='active', nullable=False))
    op.create_check_constraint('users_status_valid', 'users', "status IN ('active', 'suspended')")
    op.create_table(
        'audit_logs',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('actor_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='RESTRICT', name='audit_logs_actor_id_fkey')),
        sa.Column('action', sa.String(64), nullable=False),
        sa.Column('target_type', sa.String(64), nullable=False),
        sa.Column('target_id', sa.Uuid()),
        sa.Column('metadata', sa.JSON(), server_default='{}', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    for name, cols in [('actor_id', ['actor_id']), ('action', ['action']), ('target_type', ['target_type']), ('target_id', ['target_id']), ('created_at', ['created_at'])]:
        op.create_index('ix_audit_logs_' + name, 'audit_logs', cols)



def downgrade():
    for name in ('created_at', 'target_id', 'target_type', 'action', 'actor_id'):
        op.drop_index('ix_audit_logs_' + name, table_name='audit_logs')
    op.drop_table('audit_logs')
    op.drop_constraint('users_status_valid', 'users', type_='check')
    op.drop_column('users', 'status')

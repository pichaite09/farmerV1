"""Enforce append-only audit history for databases already at 0019."""
from alembic import op
import sqlalchemy as sa

revision = '0020_audit_immutability'
down_revision = '0019_admin_users_audit'
branch_labels = None
depends_on = None


def _create_trigger():
    op.execute(sa.text('''
        CREATE OR REPLACE FUNCTION audit_logs_append_only()
        RETURNS trigger
        LANGUAGE plpgsql
        AS $$
        BEGIN
            RAISE EXCEPTION 'audit_logs is append-only';
        END;
        $$
    '''))
    op.execute(sa.text('''
        CREATE TRIGGER audit_logs_append_only_trigger
        BEFORE UPDATE OR DELETE ON audit_logs
        FOR EACH ROW EXECUTE FUNCTION audit_logs_append_only()
    '''))


def upgrade():
    op.drop_constraint('audit_logs_actor_id_fkey', 'audit_logs', type_='foreignkey')
    op.create_foreign_key(
        'audit_logs_actor_id_fkey', 'audit_logs', 'users', ['actor_id'], ['id'], ondelete='RESTRICT'
    )
    _create_trigger()


def downgrade():
    op.execute(sa.text('DROP TRIGGER IF EXISTS audit_logs_append_only_trigger ON audit_logs'))
    op.execute(sa.text('DROP FUNCTION IF EXISTS audit_logs_append_only()'))
    op.drop_constraint('audit_logs_actor_id_fkey', 'audit_logs', type_='foreignkey')
    op.create_foreign_key(
        'audit_logs_actor_id_fkey', 'audit_logs', 'users', ['actor_id'], ['id'], ondelete='SET NULL'
    )
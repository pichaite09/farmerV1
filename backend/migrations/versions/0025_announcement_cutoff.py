"""Persist a one-way activation boundary; never replay historical announcements."""
from alembic import op

revision = '0025_announcement_cutoff'
down_revision = '0024_announce_attach'
branch_labels = None
depends_on = None


def upgrade():
    # Wait for in-flight writes before defining the activation boundary. The old
    # scheduler MUST be stopped before this migration is applied in production.
    op.execute('LOCK TABLE announcements, notifications IN SHARE ROW EXCLUSIVE MODE')
    op.execute('''CREATE TABLE announcement_delivery_policy (
        singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
        activated_at timestamptz NOT NULL
    )''')
    op.execute('''INSERT INTO announcement_delivery_policy(singleton, activated_at)
        SELECT true, GREATEST(clock_timestamp(),
            COALESCE((SELECT max(created_at) FROM announcements), '-infinity'::timestamptz),
            COALESCE((SELECT max(created_at) FROM notifications WHERE kind='admin_announcement' OR announcement_id IS NOT NULL), '-infinity'::timestamptz)
        ) + interval '1 microsecond' ''')
    op.execute('''CREATE FUNCTION protect_announcement_delivery_policy() RETURNS trigger
        LANGUAGE plpgsql AS $$ BEGIN
        RAISE EXCEPTION 'announcement delivery activation boundary is immutable';
        END $$''')
    op.execute('''CREATE TRIGGER announcement_delivery_policy_immutable
        BEFORE UPDATE OR DELETE OR TRUNCATE ON announcement_delivery_policy
        FOR EACH STATEMENT EXECUTE FUNCTION protect_announcement_delivery_policy()''')


def downgrade():
    raise RuntimeError('Refusing to remove the no-replay boundary; keep scheduler stopped for rollback')

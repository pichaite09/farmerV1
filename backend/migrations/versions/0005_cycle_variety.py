"""Add variety to production cycles."""
from alembic import op
import sqlalchemy as sa

revision = '0005_cycle_variety'
down_revision = '0004_attachments'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('production_cycles', sa.Column('variety', sa.String(200), nullable=False, server_default=''))

def downgrade():
    op.drop_column('production_cycles', 'variety')
"""Replace the editable age field with a birth date."""
from alembic import op
import sqlalchemy as sa

revision = '0010_birth_date'
down_revision = '0009_user_profile'
branch_labels = None
depends_on = None


def upgrade():
    # Keep legacy age data untouched; a numeric age cannot be converted to an
    # exact birth date without the original month/day. New data uses birth_date.
    op.add_column('users', sa.Column('birth_date', sa.Date(), nullable=True))


def downgrade():
    op.drop_column('users', 'birth_date')

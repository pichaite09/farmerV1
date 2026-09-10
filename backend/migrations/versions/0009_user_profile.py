"""Add editable farmer profile fields to users."""
from alembic import op
import sqlalchemy as sa

revision = '0009_user_profile'
down_revision = '0008_notification_dismissed'
branch_labels = None
depends_on = None


def upgrade():
    for name, column in [
        ('first_name', sa.Column('first_name', sa.String(100), nullable=True)),
        ('last_name', sa.Column('last_name', sa.String(100), nullable=True)),
        ('age', sa.Column('age', sa.Integer(), nullable=True)),
        ('house_number', sa.Column('house_number', sa.String(100), nullable=True)),
        ('subdistrict', sa.Column('subdistrict', sa.String(150), nullable=True)),
        ('district', sa.Column('district', sa.String(150), nullable=True)),
        ('province', sa.Column('province', sa.String(150), nullable=True)),
        ('phone', sa.Column('phone', sa.String(30), nullable=True)),
    ]:
        op.add_column('users', column)


def downgrade():
    for name in ('phone', 'province', 'district', 'subdistrict', 'house_number', 'age', 'last_name', 'first_name'):
        op.drop_column('users', name)

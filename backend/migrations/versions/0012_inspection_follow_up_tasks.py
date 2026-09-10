"""Link follow-up tasks to field inspections."""
from alembic import op
import sqlalchemy as sa

revision = '0012_inspection_follow_up_tasks'
down_revision = '0011_field_inspections'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        'field_inspections',
        sa.Column('follow_up_task_id', sa.Uuid(), nullable=True),
    )
    op.create_foreign_key(
        'fk_field_inspections_follow_up_task_id',
        'field_inspections', 'tasks', ['follow_up_task_id'], ['id'],
        ondelete='SET NULL',
    )
    op.create_index(
        'ix_field_inspections_follow_up_task_id',
        'field_inspections', ['follow_up_task_id'], unique=True,
    )


def downgrade():
    op.drop_index('ix_field_inspections_follow_up_task_id', table_name='field_inspections')
    op.drop_constraint('fk_field_inspections_follow_up_task_id', 'field_inspections', type_='foreignkey')
    op.drop_column('field_inspections', 'follow_up_task_id')

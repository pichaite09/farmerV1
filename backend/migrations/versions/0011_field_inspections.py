"""Add field inspections and allow multiple inspection attachments."""
from alembic import op
import sqlalchemy as sa

revision = '0011_field_inspections'
down_revision = '0010_birth_date'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'field_inspections',
        sa.Column('id', sa.Uuid(), primary_key=True),
        sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('plot_id', sa.Uuid(), sa.ForeignKey('plots.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('cycle_id', sa.Uuid(), sa.ForeignKey('production_cycles.id', ondelete='RESTRICT'), nullable=True),
        sa.Column('inspection_date', sa.Date(), nullable=False),
        sa.Column('overall_status', sa.String(32), nullable=False),
        sa.Column('checklist', sa.JSON(), nullable=False),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('recommendation', sa.Text(), nullable=True),
        sa.Column('follow_up_required', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('follow_up_date', sa.Date(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('ix_field_inspections_owner_id', 'field_inspections', ['owner_id'])
    op.create_index('ix_field_inspections_plot_id', 'field_inspections', ['plot_id'])
    op.create_index('ix_field_inspections_cycle_id', 'field_inspections', ['cycle_id'])
    op.drop_constraint('uq_attachment_parent', 'attachments', type_='unique')
    op.drop_constraint('attachments_parent_type_valid', 'attachments', type_='check')
    op.create_check_constraint(
        'attachments_parent_type_valid', 'attachments',
        "parent_type IN ('plot', 'activity', 'field_inspection')",
    )


def downgrade():
    op.drop_constraint('attachments_parent_type_valid', 'attachments', type_='check')
    op.create_check_constraint('attachments_parent_type_valid', 'attachments', "parent_type IN ('plot', 'activity')")
    op.create_unique_constraint('uq_attachment_parent', 'attachments', ['parent_type', 'parent_id'])
    op.drop_index('ix_field_inspections_cycle_id', table_name='field_inspections')
    op.drop_index('ix_field_inspections_plot_id', table_name='field_inspections')
    op.drop_index('ix_field_inspections_owner_id', table_name='field_inspections')
    op.drop_table('field_inspections')

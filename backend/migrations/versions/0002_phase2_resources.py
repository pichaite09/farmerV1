"""Phase 2 plots, production cycles, and activities."""
from alembic import op
import sqlalchemy as sa
revision = '0002_phase2_resources'
down_revision = '0001_auth'
branch_labels = None
depends_on = None

def upgrade():
    plot_common = [sa.Column('id', sa.Uuid(), primary_key=True), sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False)]
    op.create_table('plots', *plot_common, sa.Column('name', sa.String(200), nullable=False), sa.Column('area', sa.Numeric(12,2), nullable=False), sa.Column('soil', sa.String(100)), sa.Column('image_url', sa.String(1000)), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()), sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()), sa.CheckConstraint('area > 0', name='plots_area_positive'))
    op.create_index('ix_plots_owner_id', 'plots', ['owner_id'])
    cycle_common = [sa.Column('id', sa.Uuid(), primary_key=True), sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False)]
    op.create_table('production_cycles', *cycle_common, sa.Column('plot_id', sa.Uuid(), sa.ForeignKey('plots.id', ondelete='RESTRICT'), nullable=False), sa.Column('name', sa.String(200), nullable=False), sa.Column('crop_type', sa.String(200), nullable=False), sa.Column('planting_method', sa.String(200), nullable=False), sa.Column('start_date', sa.Date(), nullable=False), sa.Column('status', sa.String(16), nullable=False, server_default='active'), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()), sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()), sa.CheckConstraint("status IN ('active','completed')", name='cycles_status_valid'))
    op.create_index('ix_production_cycles_owner_id', 'production_cycles', ['owner_id']); op.create_index('ix_production_cycles_plot_id', 'production_cycles', ['plot_id'])
    activity_common = [sa.Column('id', sa.Uuid(), primary_key=True), sa.Column('owner_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False)]
    op.create_table('activities', *activity_common, sa.Column('cycle_id', sa.Uuid(), sa.ForeignKey('production_cycles.id', ondelete='RESTRICT'), nullable=False), sa.Column('type', sa.String(200), nullable=False), sa.Column('description', sa.Text()), sa.Column('date', sa.Date(), nullable=False), sa.Column('image_url', sa.String(1000)), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()), sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()))
    op.create_index('ix_activities_owner_id', 'activities', ['owner_id']); op.create_index('ix_activities_cycle_id', 'activities', ['cycle_id'])

def downgrade():
    op.drop_table('activities'); op.drop_table('production_cycles'); op.drop_table('plots')

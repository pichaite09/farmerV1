from datetime import date, datetime, timezone
from decimal import Decimal
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from uuid import UUID
from app.database import get_db
from app.main import current_session
from app.models import Transaction, FuelRecord, Vehicle, Plot, ProductionCycle, Activity, Task, FieldInspection
from app.phase3 import DEFAULTS, user
router=APIRouter(prefix='/api/v1')
def bounds(frm,to):
    if frm and to and frm>to: raise HTTPException(422,'from must not exceed to')

@router.get('/dashboard')
def dashboard(frm:date|None=Query(None,alias='from'),to:date|None=Query(None),identity=Depends(current_session),db:Session=Depends(get_db)):
    bounds(frm,to)
    owner_id=user(identity).id
    today=date.today()
    if frm is None: frm=today.replace(day=1)
    if to is None: to=today
    plots_q=select(Plot).where(Plot.owner_id==owner_id)
    cycles_q=select(ProductionCycle).where(ProductionCycle.owner_id==owner_id, ProductionCycle.status=='active')
    plots=db.scalars(plots_q).all(); active=db.scalars(cycles_q).all()
    cycles_by_id={x.id:x for x in db.scalars(select(ProductionCycle).where(ProductionCycle.owner_id==owner_id)).all()}
    plots_by_id={x.id:x.name for x in plots}
    vehicles_by_id={x.id:x.name for x in db.scalars(select(Vehicle).where(Vehicle.owner_id==owner_id)).all()}
    def plot_name(cycle_id):
        cycle=cycles_by_id.get(cycle_id)
        return plots_by_id.get(cycle.plot_id) if cycle else None
    tx=db.scalars(select(Transaction).where(Transaction.owner_id==owner_id,Transaction.date>=frm,Transaction.date<=to)).all()
    fuel_rows=db.scalars(select(FuelRecord).where(FuelRecord.owner_id==owner_id,FuelRecord.date>=frm,FuelRecord.date<=to).order_by(FuelRecord.date.desc()).limit(10)).all()
    fuel_spend_rows=db.scalars(select(FuelRecord).where(FuelRecord.owner_id==owner_id,FuelRecord.date>=frm,FuelRecord.date<=to,FuelRecord.transaction_id.is_(None))).all()
    activities=db.scalars(select(Activity).where(Activity.owner_id==owner_id).order_by(Activity.date.desc(),Activity.created_at.desc()).limit(5)).all()
    recent_tx=db.scalars(select(Transaction).where(Transaction.owner_id==owner_id).order_by(Transaction.date.desc(),Transaction.created_at.desc()).limit(5)).all()
    recent_tasks=db.scalars(select(Task).where(Task.owner_id==owner_id).order_by(Task.due_date.desc(),Task.created_at.desc()).limit(5)).all()
    recent_inspections=db.scalars(select(FieldInspection).where(FieldInspection.owner_id==owner_id,FieldInspection.overall_status=='good').order_by(FieldInspection.inspection_date.desc(),FieldInspection.created_at.desc()).limit(5)).all()
    income=sum((x.amount for x in tx if x.type=='income'),Decimal('0')); expense=sum((x.amount for x in tx if x.type=='expense'),Decimal('0'))
    fuel_spend=sum((x.amount for x in fuel_spend_rows),Decimal('0'))
    expense += fuel_spend
    bycat={}
    for x in tx:
        if x.type=='expense': bycat[x.category]=bycat.get(x.category,Decimal('0'))+x.amount
    if fuel_spend: bycat['น้ำมันเชื้อเพลิง']=bycat.get('น้ำมันเชื้อเพลิง',Decimal('0'))+fuel_spend
    return {'plots':len(plots),'totalArea':sum((x.area for x in plots),Decimal('0')),'activeCycles':len(active),'income':income,'expense':expense,'profit':income-expense,'fuelSpend':fuel_spend,'expenseByCategory':[{'category':k,'amount':v} for k,v in bycat.items()],'recentTasks':[{'id':x.id,'name':x.name,'cycleId':x.cycle_id,'plotName':plot_name(x.cycle_id),'dueDate':x.due_date,'status':x.status,'description':x.description,'createdAt':x.created_at} for x in recent_tasks],'recentInspections':[{'id':x.id,'cycleId':x.cycle_id,'plotName':plot_name(x.cycle_id),'cycleName':cycles_by_id.get(x.cycle_id).name if x.cycle_id in cycles_by_id else None,'inspectionDate':x.inspection_date,'overallStatus':x.overall_status,'notes':x.notes,'createdAt':x.created_at} for x in recent_inspections],'recentActivities':[{'id':x.id,'cycleId':x.cycle_id,'plotName':plot_name(x.cycle_id),'type':x.type,'description':x.description,'date':x.date,'createdAt':x.created_at} for x in activities],'recentTransactions':[{'id':x.id,'type':x.type,'category':x.category,'item':x.item,'amount':x.amount,'date':x.date,'plotName':plot_name(x.cycle_id),'createdAt':x.created_at} for x in recent_tx],'recentFuelRecords':[{'id':x.id,'vehicleId':x.vehicle_id,'vehicleName':vehicles_by_id.get(x.vehicle_id,'ไม่พบยานพาหนะ'),'date':x.date,'fuelType':x.fuel_type,'amount':x.amount,'details':x.details} for x in fuel_rows]}
@router.get('/reports/production-cycles/summary')
def production_cycle_summary(frm:date|None=Query(None,alias='from'),to:date|None=Query(None),identity=Depends(current_session),db:Session=Depends(get_db)):
    bounds(frm,to)
    owner_id=user(identity).id
    cycles=db.scalars(select(ProductionCycle).where(ProductionCycle.owner_id==owner_id).order_by(ProductionCycle.start_date.desc(),ProductionCycle.id.desc())).all()
    if not cycles:
        return []

    cycle_ids=[cycle.id for cycle in cycles]
    plots={plot.id:plot.name for plot in db.scalars(select(Plot).where(Plot.owner_id==owner_id)).all()}

    activities_query=select(Activity).where(Activity.owner_id==owner_id,Activity.cycle_id.in_(cycle_ids))
    if frm is not None:
        activities_query=activities_query.where(Activity.date>=frm)
    if to is not None:
        activities_query=activities_query.where(Activity.date<=to)
    activities_by_cycle={cycle_id:[] for cycle_id in cycle_ids}
    for activity in db.scalars(activities_query.order_by(Activity.date.desc(),Activity.id.desc())).all():
        activities_by_cycle[activity.cycle_id].append({
            'id':activity.id,'type':activity.type,'description':activity.description,
            'date':activity.date,'createdAt':activity.created_at,
        })

    tasks_query=select(Task).where(Task.owner_id==owner_id,Task.cycle_id.in_(cycle_ids))
    if frm is not None:
        tasks_query=tasks_query.where(Task.due_date>=frm)
    if to is not None:
        tasks_query=tasks_query.where(Task.due_date<=to)
    tasks_by_cycle={cycle_id:[] for cycle_id in cycle_ids}
    for task in db.scalars(tasks_query.order_by(Task.due_date,Task.id)).all():
        tasks_by_cycle[task.cycle_id].append({
            'id':task.id,'name':task.name,'dueDate':task.due_date,'status':task.status,
            'description':task.description,'createdAt':task.created_at,
        })

    transactions_query=select(Transaction).where(
        Transaction.owner_id==owner_id,
        Transaction.cycle_id.in_(cycle_ids),
        Transaction.fuel_record_id.is_(None),
    )
    if frm is not None:
        transactions_query=transactions_query.where(Transaction.date>=frm)
    if to is not None:
        transactions_query=transactions_query.where(Transaction.date<=to)
    totals_by_cycle={cycle_id:{'income':Decimal('0'),'expense':Decimal('0')} for cycle_id in cycle_ids}
    transactions_by_cycle={cycle_id:[] for cycle_id in cycle_ids}
    for transaction in db.scalars(transactions_query.order_by(Transaction.date.desc(),Transaction.id.desc())).all():
        if transaction.type in totals_by_cycle[transaction.cycle_id]:
            totals_by_cycle[transaction.cycle_id][transaction.type] += transaction.amount
        transactions_by_cycle[transaction.cycle_id].append({
            'id':transaction.id,'type':transaction.type,'category':transaction.category,
            'item':transaction.item,'amount':transaction.amount,'date':transaction.date,
            'fuelRecordId':transaction.fuel_record_id,'createdAt':transaction.created_at,
        })

    summaries=[]
    for cycle in cycles:
        tasks=tasks_by_cycle[cycle.id]
        totals=totals_by_cycle[cycle.id]
        income=totals['income']; expense=totals['expense']
        summaries.append({
            'cycleId':cycle.id,
            'plotId':cycle.plot_id,
            'plotName':plots.get(cycle.plot_id),
            'cycleName':cycle.name,
            'startDate':cycle.start_date,
            'endDate':None,
            'status':cycle.status,
            'activities':activities_by_cycle[cycle.id],
            'activityCount':len(activities_by_cycle[cycle.id]),
            'tasks':tasks,
            'taskCount':len(tasks),
            'completedTaskCount':sum(task['status']=='completed' for task in tasks),
            'income':income,
            'expense':expense,
            'profit':income-expense,
            'transactions':transactions_by_cycle[cycle.id],
        })
    return summaries

@router.get('/reports/finance')
def finance(frm:date|None=Query(None,alias='from'),to:date|None=Query(None),cycle_id:UUID|None=None,identity=Depends(current_session),db:Session=Depends(get_db)):
    bounds(frm,to)
    q=select(Transaction).where(Transaction.owner_id==user(identity).id)
    if frm:q=q.where(Transaction.date>=frm)
    if to:q=q.where(Transaction.date<=to)
    if cycle_id:q=q.where(Transaction.cycle_id==cycle_id)
    rows=db.scalars(q).all(); income=sum((x.amount for x in rows if x.type=='income'),Decimal('0')); expense=sum((x.amount for x in rows if x.type=='expense'),Decimal('0'))
    bycat={};bycycle={}
    for x in rows:
        k=x.category;bycat[k]=bycat.get(k,Decimal('0'))+x.amount
        ck=str(x.cycle_id) if x.cycle_id else None;bycycle[ck]=bycycle.get(ck,Decimal('0'))+x.amount
    return {'income':income,'expense':expense,'profit':income-expense,'byCategory':[{'category':k,'amount':v} for k,v in bycat.items()],'byCycle':[{'cycleId':k,'amount':v} for k,v in bycycle.items()]}
@router.get('/reports/fuel')
def fuel(frm:date|None=Query(None,alias='from'),to:date|None=Query(None),vehicle_id:UUID|None=None,identity=Depends(current_session),db:Session=Depends(get_db)):
    bounds(frm,to)
    q=select(FuelRecord).where(FuelRecord.owner_id==user(identity).id)
    if frm:q=q.where(FuelRecord.date>=frm)
    if to:q=q.where(FuelRecord.date<=to)
    if vehicle_id:q=q.where(FuelRecord.vehicle_id==vehicle_id)
    rows=db.scalars(q).all(); bv={};bt={}
    for x in rows:
        bv[str(x.vehicle_id)]=bv.get(str(x.vehicle_id),Decimal('0'))+x.amount;bt[x.fuel_type]=bt.get(x.fuel_type,Decimal('0'))+x.amount
    return {'totalAmount':sum((x.amount for x in rows),Decimal('0')),'byVehicle':[{'vehicleId':k,'amount':v} for k,v in bv.items()],'byFuelType':[{'fuelType':k,'amount':v} for k,v in bt.items()]}

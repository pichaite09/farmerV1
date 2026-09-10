import 'package:flutter_test/flutter_test.dart';
import 'package:farmer/models/api_models.dart';

void main() {
  test('decodes API camelCase resources', () {
    final p = Plot.fromJson({
      'id': 'p1',
      'name': 'นาหลังบ้าน',
      'area': 2.5,
      'soil': 'ดินร่วน',
      'imageUrl': null,
    });
    expect(p.id, 'p1');
    expect(p.area, 2.5);
  });

  test('decodes production cycle and activity API payloads', () {
    final cycle = ProductionCycle.fromJson({
      'id': 'c1',
      'name': 'รอบนาปี',
      'plotId': 'p1',
      'plotName': 'แปลง 1',
      'cropType': 'ข้าว',
      'plantingMethod': 'หว่าน',
      'startDate': '2026-09-01',
      'status': 'active',
    });
    final activity = Activity.fromJson({
      'id': 'a1',
      'cycleId': 'c1',
      'type': 'เก็บเกี่ยว',
      'description': 'เกี่ยวเสร็จ',
      'date': '2026-12-01',
      'createdAt': '2026-12-01T10:00:00Z',
    });
    expect(cycle.plotId, 'p1');
    expect(cycle.startDate, DateTime(2026, 9, 1));
    expect(activity.cycleId, 'c1');
    expect(activity.type, 'เก็บเกี่ยว');
  });

  test('decodes transaction numeric amount and nullable links', () {
    final t = FarmerTransaction.fromJson({
      'id': 't1',
      'type': 'expense',
      'category': 'ปุ๋ย',
      'item': 'ยูเรีย',
      'amount': '120.50',
      'date': '2026-09-01',
      'cycleId': null,
      'fuelRecordId': null,
    });
    expect(t.amount, 120.5);
    expect(t.cycleId, isNull);
  });

  test('decodes field inspection checklist and follow-up fields', () {
    final inspection = FieldInspection.fromJson({
      'id': 'i1',
      'plotId': 'p1',
      'cycleId': 'c1',
      'inspectionDate': '2026-09-10',
      'overallStatus': 'attention',
      'checklist': {'cropHealth': true, 'pests': false},
      'notes': 'พบเพลี้ย',
      'recommendation': 'เฝ้าดูอาการ',
      'followUpRequired': true,
      'followUpDate': '2026-09-17',
      'followUpTaskId': 'task-1',
      'followUpStatus': 'pending',
    });
    expect(inspection.overallStatus, 'attention');
    expect(inspection.followUpTaskId, 'task-1');
    expect(inspection.followUpStatus, 'pending');
    expect(inspection.checklist['cropHealth'], isTrue);
    expect(inspection.followUpRequired, isTrue);
    expect(inspection.followUpDate, DateTime(2026, 9, 17));
  });

  test('decodes automatic follow-up task links and nulls safely', () {
    final task = FarmerTask.fromJson({
      'id': 'task-1',
      'name': 'ติดตามผลแปลง',
      'cycleId': 'c1',
      'dueDate': '2026-09-17',
      'status': 'pending',
      'fieldInspectionId': 'i1',
      'isAutomaticFollowUp': true,
    });
    final manual = FarmerTask.fromJson({
      'id': 'task-2',
      'name': 'งานทั่วไป',
      'cycleId': null,
      'dueDate': '2026-09-18',
      'status': 'pending',
    });
    expect(task.fieldInspectionId, 'i1');
    expect(task.isAutomaticFollowUp, isTrue);
    expect(manual.fieldInspectionId, isNull);
    expect(manual.isAutomaticFollowUp, isFalse);
  });
  test('decodes production cycle summary and excludes fuel details', () {
    final summary = ProductionCycleSummary.fromJson({
      'cycleId': 'c1',
      'cycleName': 'รอบนาปี 2569',
      'plotName': 'แปลง A',
      'status': 'active',
      'startDate': '2026-09-01',
      'endDate': null,
      'activityCount': 2,
      'taskCount': 3,
      'completedTaskCount': 1,
      'income': '10000',
      'expense': 3500,
      'profit': 6500,
      'activities': [
        {'id': 'a1', 'type': 'ให้น้ำ', 'date': '2026-09-02'},
      ],
      'tasks': [
        {
          'id': 't1',
          'name': 'ใส่ปุ๋ย',
          'status': 'pending',
          'dueDate': '2026-09-03',
        },
      ],
      'transactions': [
        {
          'id': 'x1',
          'type': 'expense',
          'category': 'ปุ๋ย',
          'item': 'ยูเรีย',
          'amount': 100,
          'date': '2026-09-04',
        },
        {
          'id': 'fuel',
          'type': 'expense',
          'category': 'น้ำมัน',
          'item': 'ดีเซล',
          'amount': 20,
          'date': '2026-09-04',
          'fuelRecordId': 'f1',
        },
      ],
    });
    expect(summary.cycleName, 'รอบนาปี 2569');
    expect(summary.pendingTaskCount, 2);
    expect(summary.activities, hasLength(1));
    expect(summary.transactions, hasLength(1));
    expect(summary.transactions.single.item, 'ยูเรีย');
  });

  test('decodes category response', () {
    final c = Categories.fromJson({
      'activityCategories': ['ให้น้ำ'],
      'expenseCategories': [],
      'incomeCategories': [],
      'soilTypes': [],
      'plantingTypes': [],
    });
    expect(c.activityCategories, ['ให้น้ำ']);
  });
}

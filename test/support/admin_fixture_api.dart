import 'dart:typed_data';

import 'package:farmer/services/farmer_api.dart';
import 'package:farmer/models/admin_models.dart';
import 'package:farmer/models/api_models.dart';

// Synthetic data only. Not imported by lib/main.dart or production builds.
class AdminFixtureApi extends FarmerApi {
  String? requestedType, requestedOwner;
  int requestedOffset = 0;
  @override
  Future<AdminDashboard> adminDashboard({String? from, String? to}) async =>
      const AdminDashboard({
        'users': 2,
        'plots': 1,
        'cycles': 1,
        'activities': 1,
        'tasks': 1,
        'notifications': 0,
      });
  @override
  Future<AdminPage<ApiUser>> adminUsers({
    String? q,
    String? role,
    String? status,
    int limit = 20,
    int offset = 0,
  }) async => AdminPage(
    total: 1,
    limit: limit,
    offset: offset,
    items: const [
      ApiUser(
        id: 'synthetic-farmer',
        email: 'synthetic@example.test',
        firstName: 'สมชาย',
        lastName: 'เกษตรดี',
        role: 'farmer',
        status: 'active',
      ),
    ],
  );
  @override
  Future<Uint8List> adminAttachmentBytes(String attachmentId) async =>
      Uint8List.fromList(const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        6,
        0,
        0,
        0,
        31,
        21,
        196,
        137,
        0,
        0,
        0,
        13,
        73,
        68,
        65,
        84,
        120,
        156,
        99,
        248,
        207,
        192,
        240,
        31,
        0,
        5,
        0,
        1,
        255,
        137,
        153,
        61,
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130,
      ]);

  @override
  Future<AdminProductionCycleDetail> adminProductionCycleDetail(
    String cycleId,
  ) async {
    final records = await adminRecords('all', cycle: cycleId);
    final children = records.items
        .where((r) => r['type'] != 'production_cycle')
        .map(AdminCycleDetailItem.fromJson)
        .toList();
    final byType = <String, List<AdminCycleDetailItem>>{
      for (final type in const [
        'activity',
        'field_inspection',
        'task',
        'transaction',
        'fuel_record',
      ])
        type: children.where((item) => item.type == type).toList(),
    };
    return AdminProductionCycleDetail(
      cycle: records.items.firstWhere((r) => r['type'] == 'production_cycle'),
      counts: {
        'activities': byType['activity']!.length,
        'fieldInspections': byType['field_inspection']!.length,
        'tasks': byType['task']!.length,
        'transactions': byType['transaction']!.length,
        'fuelRecords': byType['fuel_record']!.length,
      },
      activities: byType['activity']!,
      fieldInspections: byType['field_inspection']!,
      tasks: byType['task']!,
      transactions: byType['transaction']!,
      fuelRecords: byType['fuel_record']!,
      timeline: children,
    );
  }

  @override
  Future<AdminPage<Map<String, dynamic>>> adminRecords(
    String type, {
    String? from,
    String? to,
    String? owner,
    String? plot,
    String? cycle,
    int limit = 20,
    int offset = 0,
  }) async {
    requestedType = type;
    requestedOwner = owner;
    requestedOffset = offset;
    const types = [
      'activity',
      'field_inspection',
      'task',
      'production_cycle',
      'plot',
      'transaction',
      'fuel_record',
    ];
    final records = types
        .where((t) => type == 'all' || type == t)
        .map(
          (t) => <String, dynamic>{
            'id': 'synthetic-$t',
            'type': t,
            'cycleId': 'synthetic-production_cycle',
            'createdAt': '2026-09-11T08:00:00Z',
            if (['task', 'production_cycle', 'plot'].contains(t))
              'name': 'แปลงนาข้าวตัวอย่าง',
            if (t == 'activity') 'description': 'ปลูกข้าวฤดูฝน',
            if (t == 'activity')
              'attachments': [
                {
                  'id': 'synthetic-image',
                  'contentType': 'image/png',
                  'sizeBytes': 67,
                },
              ],
            if (t == 'transaction') 'item': 'เมล็ดพันธุ์ข้าว',
            if (t == 'fuel_record') 'fuelType': 'ดีเซล',
            'recorder': {
              'firstName': 'สมชาย',
              'lastName': 'เกษตรดี',
              'email': 'synthetic@example.test',
            },
            'plot': {'name': 'นาริมคลอง'},
            'cycle': {'name': 'ข้าวนาปี 2569'},
            'date': '2026-09-11',
          },
        )
        .toList();
    final selected = cycle == null
        ? records
        : records.where((r) => r['cycleId'] == cycle).toList();
    return AdminPage(
      total: selected.length,
      limit: limit,
      offset: offset,
      items: selected,
    );
  }
}

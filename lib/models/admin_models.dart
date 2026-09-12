import 'api_models.dart';

class AdminPage<T> {
  final int total, limit, offset;
  final List<T> items;
  const AdminPage({
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
  });
  factory AdminPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) => AdminPage(
    total: (json['total'] as num?)?.toInt() ?? 0,
    limit: (json['limit'] as num?)?.toInt() ?? 50,
    offset: (json['offset'] as num?)?.toInt() ?? 0,
    items: ((json['items'] as List?) ?? [])
        .map((v) => parse(Map<String, dynamic>.from(v as Map)))
        .toList(),
  );
}

class AdminDashboard {
  final Map<String, int> counts;
  const AdminDashboard(this.counts);
  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    final raw = json['counts'] is Map
        ? Map<String, dynamic>.from(json['counts'])
        : <String, dynamic>{};
    return AdminDashboard(
      raw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
    );
  }
}

class AdminAnnouncement {
  final String id, title, body, status, targetType;
  final int targetCount;
  final DateTime? createdAt, sentAt, cancelledAt;
  const AdminAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.targetType,
    required this.targetCount,
    this.createdAt,
    this.sentAt,
    this.cancelledAt,
  });
  factory AdminAnnouncement.fromJson(Map<String, dynamic> j) =>
      AdminAnnouncement(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        status: '${j['status'] ?? ''}',
        targetType: '${j['targetType'] ?? j['target_type'] ?? ''}',
        targetCount: (j['targetCount'] ?? j['target_count'] as num?) is num
            ? ((j['targetCount'] ?? j['target_count']) as num).toInt()
            : 0,
        createdAt: DateTime.tryParse(
          '${j['createdAt'] ?? j['created_at'] ?? ''}',
        ),
        sentAt: DateTime.tryParse('${j['sentAt'] ?? j['sent_at'] ?? ''}'),
        cancelledAt: DateTime.tryParse(
          '${j['cancelledAt'] ?? j['cancelled_at'] ?? ''}',
        ),
      );
}

class AdminAuditLog {
  final String id, action, targetType, actorId, targetId;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  const AdminAuditLog({
    required this.id,
    required this.action,
    required this.targetType,
    required this.actorId,
    required this.targetId,
    required this.metadata,
    this.createdAt,
  });
  factory AdminAuditLog.fromJson(Map<String, dynamic> j) => AdminAuditLog(
    id: '${j['id'] ?? ''}',
    action: '${j['action'] ?? ''}',
    targetType: '${j['targetType'] ?? ''}',
    actorId: '${j['actorId'] ?? ''}',
    targetId: '${j['targetId'] ?? ''}',
    metadata: j['metadata'] is Map
        ? Map<String, dynamic>.from(j['metadata'])
        : {},
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
  );
}

class AdminCycleDetailItem {
  final String id, type, title, date;
  final Map<String, dynamic> data;
  final List<Attachment> attachments;
  const AdminCycleDetailItem({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    required this.data,
    required this.attachments,
  });
  factory AdminCycleDetailItem.fromJson(Map<String, dynamic> j) {
    final date =
        j['date'] ?? j['inspectionDate'] ?? j['dueDate'] ?? j['createdAt'];
    final title =
        j['name'] ??
        j['description'] ??
        j['item'] ??
        j['fuelType'] ??
        j['activityType'] ??
        j['overallStatus'] ??
        'รายการ';
    return AdminCycleDetailItem(
      id: '${j['id'] ?? ''}',
      type: '${j['type'] ?? ''}',
      title: '$title',
      date: '$date',
      data: Map.unmodifiable(j),
      attachments: ((j['attachments'] as List?) ?? const [])
          .whereType<Map>()
          .map((x) => Attachment.fromJson(Map<String, dynamic>.from(x)))
          .toList(),
    );
  }
}

class AdminProductionCycleDetail {
  final Map<String, dynamic> cycle;
  final Map<String, int> counts;
  final List<AdminCycleDetailItem> activities,
      fieldInspections,
      tasks,
      transactions,
      fuelRecords,
      timeline;
  const AdminProductionCycleDetail({
    required this.cycle,
    required this.counts,
    required this.activities,
    required this.fieldInspections,
    required this.tasks,
    required this.transactions,
    required this.fuelRecords,
    required this.timeline,
  });
  factory AdminProductionCycleDetail.fromJson(Map<String, dynamic> j) {
    List<AdminCycleDetailItem> items(String key) =>
        ((j[key] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (x) =>
                  AdminCycleDetailItem.fromJson(Map<String, dynamic>.from(x)),
            )
            .toList();
    final rawCounts = j['counts'] is Map
        ? Map<String, dynamic>.from(j['counts'])
        : <String, dynamic>{};
    return AdminProductionCycleDetail(
      cycle: Map.unmodifiable(Map<String, dynamic>.from(j['cycle'] as Map)),
      counts: rawCounts.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      activities: items('activities'),
      fieldInspections: items('fieldInspections'),
      tasks: items('tasks'),
      transactions: items('transactions'),
      fuelRecords: items('fuelRecords'),
      timeline: items('timeline'),
    );
  }
  List<AdminCycleDetailItem> filtered(String? type) => switch (type) {
    'activity' => activities,
    'field_inspection' => fieldInspections,
    'task' => tasks,
    'transaction' => transactions,
    'fuel_record' => fuelRecords,
    _ => timeline,
  };
}

ApiUser adminUserFromJson(Map<String, dynamic> j) => ApiUser.fromJson(j);

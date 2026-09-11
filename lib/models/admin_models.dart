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

ApiUser adminUserFromJson(Map<String, dynamic> j) => ApiUser.fromJson(j);

import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class OfflineQueueStore {
  Future<List<Map<String, dynamic>>> read({String? userId});
  Future<void> write(List<Map<String, dynamic>> values, {String? userId});
}

class SharedPreferencesOfflineQueueStore implements OfflineQueueStore {
  static const key = 'farmer_offline_queue_v1';
  String _key(String? userId) => userId == null ? key : '$key.$userId';
  @override
  Future<List<Map<String, dynamic>>> read({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_key(userId));
    // Read the pre-user-isolation queue only for the authenticated user. It is
    // never returned wholesale and is migrated on the next user-scoped write.
    if (raw == null && userId != null) raw = prefs.getString(key);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .where((e) => userId == null || e['userId'] == userId)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> write(
    List<Map<String, dynamic>> values, {
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), jsonEncode(values));
  }
}

class MemoryOfflineQueueStore implements OfflineQueueStore {
  List<Map<String, dynamic>> values = [];
  final Map<String, List<Map<String, dynamic>>> _byUser = {};
  @override
  Future<List<Map<String, dynamic>>> read({String? userId}) async {
    final source = userId == null ? values : (_byUser[userId] ?? const []);
    return source.map(Map<String, dynamic>.from).toList();
  }

  @override
  Future<void> write(
    List<Map<String, dynamic>> values, {
    String? userId,
  }) async {
    final copy = values.map(Map<String, dynamic>.from).toList();
    if (userId == null) {
      this.values = copy;
    } else {
      _byUser[userId] = copy;
    }
  }
}

class OfflineQueueEntry {
  final String id;
  final String userId;
  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final String idempotencyKey;
  final DateTime createdAt;
  final String? lastError;
  final String status;

  const OfflineQueueEntry({
    required this.id,
    required this.userId,
    required this.method,
    required this.path,
    required this.body,
    required this.idempotencyKey,
    required this.createdAt,
    this.lastError,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'method': method,
    'path': path,
    if (body != null) 'body': body,
    'idempotencyKey': idempotencyKey,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lastError': lastError,
    'status': status,
  };

  factory OfflineQueueEntry.fromJson(Map<String, dynamic> json) =>
      OfflineQueueEntry(
        id: json['id'] as String,
        userId: json['userId'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        body: json['body'] == null
            ? null
            : Map<String, dynamic>.from(json['body'] as Map),
        idempotencyKey: json['idempotencyKey'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastError: json['lastError'] as String?,
        status: (json['status'] as String?) ?? 'pending',
      );
}

class OfflineQueue {
  final OfflineQueueStore store;
  static Future<void> _operationTail = Future<void>.value();

  OfflineQueue({OfflineQueueStore? store})
    : store = store ?? SharedPreferencesOfflineQueueStore();

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _operationTail;
    final completed = Completer<void>();
    _operationTail = completed.future;
    await previous;
    try {
      return await operation();
    } finally {
      completed.complete();
    }
  }

  Future<List<OfflineQueueEntry>> entriesForUser(String userId) async =>
      (await store.read(userId: userId))
          .map(OfflineQueueEntry.fromJson)
          .where((e) => e.userId == userId)
          .toList();

  Future<void> enqueue(OfflineQueueEntry entry) async {
    await _serialized(() async {
      final all = await store.read(userId: entry.userId);
      all.add(entry.toJson());
      await store.write(all, userId: entry.userId);
    });
  }

  Future<void> flush(
    String userId,
    Future<void> Function(OfflineQueueEntry) replay, {
    bool Function(Object error)? isBlocked,
  }) async {
    await _serialized(() async {
      final all = (await store.read(
        userId: userId,
      )).map(OfflineQueueEntry.fromJson).toList();
      for (final entry
          in all
              .where((e) => e.userId == userId && e.status == 'pending')
              .toList()) {
        try {
          await replay(entry);
          all.removeWhere((e) => e.id == entry.id);
        } catch (e) {
          final i = all.indexWhere((x) => x.id == entry.id);
          all[i] = OfflineQueueEntry(
            id: entry.id,
            userId: entry.userId,
            method: entry.method,
            path: entry.path,
            body: entry.body,
            idempotencyKey: entry.idempotencyKey,
            createdAt: entry.createdAt,
            lastError: e.toString(),
            status:
                isBlocked?.call(e) == true ||
                    e.toString().contains(RegExp(r'\b(401|403|422)\b'))
                ? 'blocked'
                : 'pending',
          );
          if (all[i].status == 'blocked') break;
          if (e is! Exception) rethrow;
        }
      }
      await store.write(all.map((e) => e.toJson()).toList(), userId: userId);
    });
  }
}

class OfflineQueuedException implements Exception {
  final String message;
  const OfflineQueuedException([
    this.message = 'บันทึกไว้แล้ว จะซิงค์เมื่อเชื่อมต่ออินเทอร์เน็ต',
  ]);
  @override
  String toString() => message;
}

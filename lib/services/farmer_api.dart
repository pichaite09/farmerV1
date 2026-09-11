import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'offline_queue.dart';
import '../models/api_models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class FarmerApi {
  final String baseUrl;
  final http.Client client;
  OfflineQueue? offlineQueue;
  Future<void> Function()? onQueued;
  String? token;
  String? queueUserId;
  FarmerApi({String? baseUrl, http.Client? client, this.offlineQueue})
    : client = client ?? http.Client(),
      baseUrl = (baseUrl ?? _configuredBaseUrl()).replaceAll(RegExp(r'/$'), '');
  static String _configuredBaseUrl() {
    const configured = String.fromEnvironment('FARM_API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb && Uri.base.host.isNotEmpty) return Uri.base.origin;
    return 'http://localhost:8090';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool allowQueue = true,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1$path',
    ).replace(queryParameters: query);
    final idempotencyKey =
        headers?['Idempotency-Key'] ??
        (method == 'POST' ? _newIdempotencyKey() : null);
    final req = http.Request(method, uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        ...?headers,
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (body != null) req.body = jsonEncode(body);
    try {
      final res = await client.send(req);
      final text = await res.stream.bytesToString();
      dynamic data;
      if (text.isNotEmpty) {
        try {
          data = jsonDecode(text);
        } catch (_) {
          data = text;
        }
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final m = data is Map ? (data['message'] ?? data['detail']) : null;
        final detail = m is List
            ? m.map((x) => x is Map ? x['msg'] ?? x : x).join(', ')
            : m?.toString();
        throw ApiException(res.statusCode, detail ?? 'เชื่อมต่อ API ไม่สำเร็จ');
      }
      return data;
    } catch (e) {
      if (allowQueue &&
          _isWrite(method) &&
          offlineQueue != null &&
          queueUserId != null &&
          e is! ApiException) {
        await offlineQueue!.enqueue(
          OfflineQueueEntry(
            id: _newIdempotencyKey(),
            userId: queueUserId!,
            method: method,
            path: path,
            body: body,
            idempotencyKey: idempotencyKey ?? _newIdempotencyKey(),
            createdAt: DateTime.now(),
          ),
        );
        await onQueued?.call();
        throw const OfflineQueuedException();
      }
      rethrow;
    }
  }

  static bool _isWrite(String method) => method != 'GET' && method != 'HEAD';
  static String _newIdempotencyKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Object().hashCode}';

  Future<void> replayQueued(OfflineQueueEntry entry) async {
    if (entry.path == '/attachments') {
      final body = entry.body;
      if (body == null) throw const FormatException('ข้อมูลรูปภาพในคิวไม่ครบ');
      final bytes = base64Decode(body['bytesBase64'] as String);
      _validateImage(bytes, body['contentType'] as String);
      await _sendAttachment(
        parentType: body['parentType'] as String,
        parentId: body['parentId'] as String,
        filename: body['filename'] as String,
        contentType: body['contentType'] as String,
        bytes: bytes,
        idempotencyKey: entry.idempotencyKey,
      );
      return;
    }
    await _request(
      entry.method,
      entry.path,
      body: entry.body,
      headers: {'Idempotency-Key': entry.idempotencyKey},
      allowQueue: false,
    );
  }

  Future<Map<String, dynamic>> login(String e, String p) => _request(
    'POST',
    '/auth/login',
    body: {'email': e, 'password': p},
  ).then(_map);
  Future<Map<String, dynamic>> register(String e, String p) => _request(
    'POST',
    '/auth/register',
    body: {'email': e, 'password': p},
  ).then(_map);
  Future<Map<String, dynamic>> me() => _request('GET', '/auth/me').then(_map);
  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> body) =>
      _request('PATCH', '/auth/me', body: body).then(_map);
  Future<void> logout() => _request('POST', '/auth/logout').then((_) {});
  Map<String, dynamic> _map(dynamic v) => Map<String, dynamic>.from(v as Map);
  Map<String, dynamic> _resourceMap(dynamic v) {
    final map = Map<String, dynamic>.from(v as Map);
    final data = map['data'];
    return data is Map ? Map<String, dynamic>.from(data) : map;
  }

  Future<List<T>> list<T>(
    String path,
    T Function(Map<String, dynamic>) from, {
    Map<String, String>? query,
  }) async {
    final v = await _request('GET', path, query: query);
    final raw = v is Map && v['items'] is List ? v['items'] : v;
    return (raw as List)
        .map((e) => from(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Plot> createPlot(String name, double area, String? soil) => _request(
    'POST',
    '/plots',
    body: {'name': name, 'area': area, 'soil': soil},
  ).then((v) => Plot.fromJson(_resourceMap(v)));
  Future<Plot> updatePlot(String id, String name, double area, String? soil) =>
      _request(
        'PATCH',
        '/plots/$id',
        body: {'name': name, 'area': area, 'soil': soil},
      ).then((v) => Plot.fromJson(_resourceMap(v)));
  Future<void> deletePlot(String id) => delete('/plots/$id');
  Future<List<Plot>> plots() => list('/plots', Plot.fromJson);
  Future<Attachment> uploadAttachment({
    required String parentType,
    required String parentId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final contentType = _contentTypeFor(file.name);
    _validateImage(bytes, contentType);
    final idempotencyKey = _newIdempotencyKey();
    final body = {
      'parentType': parentType,
      'parentId': parentId,
      'filename': file.name,
      'contentType': contentType,
      'bytesBase64': base64Encode(bytes),
    };
    try {
      return await _sendAttachment(
        parentType: parentType,
        parentId: parentId,
        filename: file.name,
        contentType: contentType,
        bytes: bytes,
        idempotencyKey: idempotencyKey,
      );
    } catch (e) {
      if (e is! ApiException && offlineQueue != null && queueUserId != null) {
        await offlineQueue!.enqueue(
          OfflineQueueEntry(
            id: _newIdempotencyKey(),
            userId: queueUserId!,
            method: 'POST',
            path: '/attachments',
            body: body,
            idempotencyKey: idempotencyKey,
            createdAt: DateTime.now(),
          ),
        );
        await onQueued?.call();
        throw const OfflineQueuedException();
      }
      rethrow;
    }
  }

  String _contentTypeFor(String filename) {
    final name = filename.toLowerCase();
    final extension = name.contains('.')
        ? name.substring(name.lastIndexOf('.'))
        : '';
    return switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => throw const FormatException('รองรับเฉพาะ JPEG, PNG หรือ WebP'),
    };
  }

  void _validateImage(List<int> bytes, String contentType) {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('รูปภาพต้องมีขนาดไม่เกิน 10 MiB');
    }
    if (!_hasImageSignature(bytes, contentType)) {
      throw const FormatException('ชนิดไฟล์รูปภาพไม่ตรงกับนามสกุล');
    }
  }

  Future<Attachment> _sendAttachment({
    required String parentType,
    required String parentId,
    required String filename,
    required String contentType,
    required List<int> bytes,
    String? idempotencyKey,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/attachments'))
          ..fields['parentType'] = parentType
          ..fields['parentId'] = parentId
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename,
              contentType: _mediaType(contentType),
            ),
          );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    final response = await client.send(request);
    final text = await response.stream.bytesToString();
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = text;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data is Map ? (data['message'] ?? data['detail']) : null;
      throw ApiException(
        response.statusCode,
        message?.toString() ?? 'อัปโหลดรูปภาพไม่สำเร็จ',
      );
    }
    return Attachment.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<Attachment>> uploadAttachments({
    required String parentType,
    required String parentId,
    required List<XFile> files,
  }) async {
    final uploaded = <Attachment>[];
    var queued = false;
    for (final file in files) {
      try {
        uploaded.add(
          await uploadAttachment(
            parentType: parentType,
            parentId: parentId,
            file: file,
          ),
        );
      } on OfflineQueuedException {
        queued = true;
      }
    }
    if (queued) throw const OfflineQueuedException();
    return uploaded;
  }

  Future<List<FieldInspection>> fieldInspections({String? cycleId}) => list(
    '/field-inspections',
    FieldInspection.fromJson,
    query: cycleId == null ? null : {'cycleId': cycleId},
  );
  Future<FieldInspection> createFieldInspection(Map<String, dynamic> body) =>
      _request(
        'POST',
        '/field-inspections',
        body: body,
      ).then((v) => FieldInspection.fromJson(_resourceMap(v)));
  Future<FieldInspection> updateFieldInspection(
    String id,
    Map<String, dynamic> body,
  ) => _request(
    'PATCH',
    '/field-inspections/$id',
    body: body,
  ).then((v) => FieldInspection.fromJson(_resourceMap(v)));
  Future<void> deleteFieldInspection(String id) =>
      delete('/field-inspections/$id');

  Future<List<Attachment>> attachments(
    String parentType,
    String parentId,
  ) async {
    final value = await _request(
      'GET',
      '/attachments',
      query: {'parentType': parentType, 'parentId': parentId},
    );
    return (value as List)
        .map((e) => Attachment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Uint8List> attachmentContent(String attachmentId) async {
    final response = await client.get(
      Uri.parse('$baseUrl/api/v1/attachments/$attachmentId/content'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'โหลดรูปภาพไม่สำเร็จ');
    }
    return response.bodyBytes;
  }

  Future<void> deleteAttachment(String attachmentId) =>
      delete('/attachments/$attachmentId');

  static bool _hasImageSignature(List<int> bytes, String type) {
    if (type == 'image/jpeg')
      return bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
    if (type == 'image/png')
      return bytes.length >= 8 &&
          const [
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
          ].asMap().entries.every((e) => bytes[e.key] == e.value);
    return bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
  }

  static MediaType _mediaType(String value) {
    final parts = value.split('/');
    return MediaType(parts[0], parts[1]);
  }

  Future<ProductionCycle> createCycle(Map<String, dynamic> b) => _request(
    'POST',
    '/cycles',
    body: b,
  ).then((v) => ProductionCycle.fromJson(_resourceMap(v)));
  Future<ProductionCycle> updateCycle(String id, Map<String, dynamic> b) =>
      _request(
        'PATCH',
        '/cycles/$id',
        body: b,
      ).then((v) => ProductionCycle.fromJson(_resourceMap(v)));
  Future<void> deleteCycle(String id) => delete('/cycles/$id');
  Future<List<ProductionCycle>> cycles() =>
      list('/cycles', ProductionCycle.fromJson);
  Future<List<ProductionCycleSummary>> productionCycleSummaries({
    DateTime? from,
    DateTime? to,
  }) async {
    final value = await _request(
      'GET',
      '/reports/production-cycles/summary',
      query: {
        if (from != null) 'from': from.toIso8601String().split('T').first,
        if (to != null) 'to': to.toIso8601String().split('T').first,
      },
    );
    final raw = value is Map ? value['cycles'] : value;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (x) => ProductionCycleSummary.fromJson(Map<String, dynamic>.from(x)),
        )
        .toList();
  }

  Future<Activity> createActivity(Map<String, dynamic> b) => _request(
    'POST',
    '/activities',
    body: b,
  ).then((v) => Activity.fromJson(_resourceMap(v)));
  Future<Activity> updateActivity(String id, Map<String, dynamic> b) =>
      _request(
        'PATCH',
        '/activities/$id',
        body: b,
      ).then((v) => Activity.fromJson(_resourceMap(v)));
  Future<void> deleteActivity(String id) => delete('/activities/$id');
  Future<List<Activity>> activities({String? cycleId}) => list(
    '/activities',
    Activity.fromJson,
    query: {if (cycleId != null) 'cycle_id': cycleId},
  );
  Future<FarmerTransaction> createTransaction(Map<String, dynamic> b) =>
      _request(
        'POST',
        '/transactions',
        body: b,
      ).then((v) => FarmerTransaction.fromJson(v));
  Future<FarmerTransaction> updateTransaction(
    String id,
    Map<String, dynamic> b,
  ) => _request(
    'PATCH',
    '/transactions/$id',
    body: b,
  ).then((v) => FarmerTransaction.fromJson(v));
  Future<List<FarmerTransaction>> transactions() =>
      list('/transactions', FarmerTransaction.fromJson);
  Future<Vehicle> createVehicle(Map<String, dynamic> b) =>
      _request('POST', '/vehicles', body: b).then((v) => Vehicle.fromJson(v));
  Future<Vehicle> updateVehicle(String id, Map<String, dynamic> b) => _request(
    'PATCH',
    '/vehicles/$id',
    body: b,
  ).then((v) => Vehicle.fromJson(v));
  Future<List<Vehicle>> vehicles() => list('/vehicles', Vehicle.fromJson);
  Future<FuelRecord> createFuelRecord(Map<String, dynamic> b) => _request(
    'POST',
    '/fuel-records',
    body: b,
  ).then((v) => FuelRecord.fromJson(v));
  Future<FuelRecord> updateFuelRecord(String id, Map<String, dynamic> b) =>
      _request(
        'PATCH',
        '/fuel-records/$id',
        body: b,
      ).then((v) => FuelRecord.fromJson(v));
  Future<List<FuelRecord>> fuelRecords() =>
      list('/fuel-records', FuelRecord.fromJson);
  Future<FarmerTask> createTask(Map<String, dynamic> b) =>
      _request('POST', '/tasks', body: b).then((v) => FarmerTask.fromJson(v));
  Future<FarmerTask> updateTask(String id, Map<String, dynamic> b) => _request(
    'PATCH',
    '/tasks/$id',
    body: b,
  ).then((v) => FarmerTask.fromJson(v));
  Future<List<FarmerTask>> tasks({String? cycleId}) => list(
    '/tasks',
    FarmerTask.fromJson,
    query: cycleId == null ? null : {'cycleId': cycleId},
  );
  Future<List<FarmerNotification>> notifications() =>
      list('/notifications', FarmerNotification.fromJson);
  Future<FarmerNotification> markNotificationRead(String id) => _request(
    'PATCH',
    '/notifications/$id/read',
  ).then((v) => FarmerNotification.fromJson(v));
  Future<void> clearReadNotifications() =>
      _request('DELETE', '/notifications/read', allowQueue: false).then((_) {});
  Future<Map<String, dynamic>> vapidPublicKey() =>
      _request('GET', '/push/vapid-public-key').then(_map);
  Future<Map<String, dynamic>> registerPushSubscription(
    Map<String, dynamic> subscription,
  ) => _request(
    'POST',
    '/push/subscriptions',
    body: subscription,
    allowQueue: false,
  ).then(_map);
  Future<void> deletePushSubscription(String subscriptionId) => _request(
    'DELETE',
    '/push/subscriptions/$subscriptionId',
    allowQueue: false,
  ).then((_) {});
  Future<Categories> categories() => _request(
    'GET',
    '/settings/categories',
  ).then((v) => Categories.fromJson(v));
  Future<Categories> updateCategory(
    String key,
    List<String> values, {
    String? ifMatch,
  }) => _request(
    'PUT',
    '/settings/categories/$key',
    body: {'values': values},
    headers: {if (ifMatch != null) 'If-Match': ifMatch},
  ).then((v) => Categories.fromJson(v));
  Future<Map<String, dynamic>> dashboard({String? from, String? to}) =>
      _request(
        'GET',
        '/dashboard',
        query: {if (from != null) 'from': from, if (to != null) 'to': to},
      ).then(_map);
  Future<Map<String, dynamic>> report(
    String kind, {
    Map<String, String>? query,
  }) => _request('GET', '/reports/$kind', query: query).then(_map);
  Future<Map<String, dynamic>> fuelReport({
    String? from,
    String? to,
    String? vehicleId,
  }) => _request(
    'GET',
    '/reports/fuel',
    query: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (vehicleId != null) 'vehicle_id': vehicleId,
    },
  ).then(_map);
  Future<void> delete(String path) => _request('DELETE', path).then((_) {});
}

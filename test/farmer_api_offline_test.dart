import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:farmer/services/farmer_api.dart';
import 'package:farmer/services/offline_queue.dart';

class FakeClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  FakeClient(this.handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

http.StreamedResponse response(int status, String body) =>
    http.StreamedResponse(Stream<List<int>>.value(body.codeUnits), status);

void main() {
  test('network write is queued without pretending it succeeded', () async {
    final store = MemoryOfflineQueueStore();
    final api = FarmerApi(
      client: FakeClient((_) async => throw const SocketException('offline')),
      offlineQueue: OfflineQueue(store: store),
    )..queueUserId = 'user-a';

    await expectLater(
      api.createTask({'name': 'irrigate'}),
      throwsA(isA<OfflineQueuedException>()),
    );
    final queued = await OfflineQueue(store: store).entriesForUser('user-a');
    expect(queued.single.path, '/tasks');
    expect(queued.single.method, 'POST');
  });

  test('HTTP validation failure is surfaced and never queued', () async {
    final store = MemoryOfflineQueueStore();
    final api = FarmerApi(
      client: FakeClient((_) async => response(422, '{"message":"invalid"}')),
      offlineQueue: OfflineQueue(store: store),
    )..queueUserId = 'user-a';

    await expectLater(
      api.createTask({'name': ''}),
      throwsA(predicate((e) => e is ApiException && e.statusCode == 422)),
    );
    expect(await OfflineQueue(store: store).entriesForUser('user-a'), isEmpty);
  });

  test('queued replay sends auth and stable idempotency headers', () async {
    late http.BaseRequest seen;
    final api = FarmerApi(
      client: FakeClient((request) async {
        seen = request;
        return response(201, '{"id":"t1","name":"x"}');
      }),
    )..token = 'token-a';
    final e = OfflineQueueEntry(
      id: 'q',
      userId: 'user-a',
      method: 'POST',
      path: '/tasks',
      body: {'name': 'x'},
      idempotencyKey: 'idem-q',
      createdAt: DateTime.utc(2026),
    );

    await api.replayQueued(e);
    expect(seen.headers['authorization'], 'Bearer token-a');
    expect(seen.headers['idempotency-key'], 'idem-q');
  });

  test('attachment upload builds authenticated multipart request and is never queued', () async {
    final temp = await File('${Directory.systemTemp.path}/field.jpg').writeAsBytes([0xff, 0xd8, 0xff, 0xe0]);
    final queue = OfflineQueue(store: MemoryOfflineQueueStore());
    late http.BaseRequest seen;
    final api = FarmerApi(client: FakeClient((request) async {
      seen = request;
      return response(201, '{"id":"a1","parentType":"plot","parentId":"p1","contentType":"image/jpeg","sizeBytes":4,"createdAt":"2026-01-01T00:00:00Z","contentUrl":"/api/v1/attachments/a1/content"}');
    }), offlineQueue: queue)..token = 'token-a'..queueUserId = 'user-a';
    final attachment = await api.uploadAttachment(
      parentType: 'plot', parentId: 'p1',
      file: XFile(temp.path),
    );
    expect(attachment.id, 'a1');
    expect(seen, isA<http.MultipartRequest>());
    expect(seen.headers['authorization'], 'Bearer token-a');
    final body = await (seen as http.MultipartRequest).finalize().fold<List<int>>([], (a, b) => a..addAll(b));
    final text = String.fromCharCodes(body);
    expect(text, contains('name="parentType"'));
    expect(text, contains('name="parentId"'));
    expect(text, contains('field.jpg'));
    expect(await queue.entriesForUser('user-a'), isEmpty);
    await temp.delete();
  });

  test('invalid attachment is rejected before transport', () async {
    var called = false;
    final api = FarmerApi(client: FakeClient((_) async {
      called = true;
      return response(201, '{}');
    }));
    await expectLater(
      api.uploadAttachment(parentType: 'plot', parentId: 'p1', file: XFile.fromData(Uint8List.fromList([1, 2]), name: 'field.gif')),
      throwsA(isA<FormatException>()),
    );
    expect(called, isFalse);
  });
}

import 'dart:async';
import 'dart:convert';
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

  test(
    'attachment upload builds authenticated multipart request and is never queued',
    () async {
      final temp = await File(
        '${Directory.systemTemp.path}/field.jpg',
      ).writeAsBytes([0xff, 0xd8, 0xff, 0xe0]);
      final queue = OfflineQueue(store: MemoryOfflineQueueStore());
      late http.BaseRequest seen;
      final api =
          FarmerApi(
              client: FakeClient((request) async {
                seen = request;
                return response(
                  201,
                  '{"id":"a1","parentType":"plot","parentId":"p1","contentType":"image/jpeg","sizeBytes":4,"createdAt":"2026-01-01T00:00:00Z","contentUrl":"/api/v1/attachments/a1/content"}',
                );
              }),
              offlineQueue: queue,
            )
            ..token = 'token-a'
            ..queueUserId = 'user-a';
      final attachment = await api.uploadAttachment(
        parentType: 'plot',
        parentId: 'p1',
        file: XFile(temp.path),
      );
      expect(attachment.id, 'a1');
      expect(seen, isA<http.MultipartRequest>());
      expect(seen.headers['authorization'], 'Bearer token-a');
      expect(seen.headers['idempotency-key'], isNotEmpty);
      final body = await (seen as http.MultipartRequest)
          .finalize()
          .fold<List<int>>([], (a, b) => a..addAll(b));
      final text = String.fromCharCodes(body);
      expect(text, contains('name="parentType"'));
      expect(text, contains('name="parentId"'));
      expect(text, contains('field.jpg'));
      expect(await queue.entriesForUser('user-a'), isEmpty);
      await temp.delete();
    },
  );

  test('invalid attachment is rejected before transport', () async {
    var called = false;
    final api = FarmerApi(
      client: FakeClient((_) async {
        called = true;
        return response(201, '{}');
      }),
    );
    await expectLater(
      api.uploadAttachment(
        parentType: 'plot',
        parentId: 'p1',
        file: XFile.fromData(Uint8List.fromList([1, 2]), name: 'field.gif'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(called, isFalse);
  });

  test('offline attachment is queued as its own durable file entry', () async {
    final store = MemoryOfflineQueueStore();
    final api = FarmerApi(
      client: FakeClient((_) async => throw const SocketException('offline')),
      offlineQueue: OfflineQueue(store: store),
    )..queueUserId = 'user-a';

    await expectLater(
      api.uploadAttachment(
        parentType: 'task',
        parentId: 'task-1',
        file: XFile(
          (await File(
            '${Directory.systemTemp.path}/queued-field.jpg',
          ).writeAsBytes([0xff, 0xd8, 0xff, 0xe0])).path,
        ),
      ),
      throwsA(isA<OfflineQueuedException>()),
    );

    final queued = await OfflineQueue(store: store).entriesForUser('user-a');
    expect(queued, hasLength(1));
    expect(queued.single.path, '/attachments');
    expect(queued.single.body, containsPair('parentId', 'task-1'));
    expect(queued.single.body, containsPair('filename', 'queued-field.jpg'));
    expect(queued.single.body?['bytesBase64'], isNotEmpty);
  });

  test('each offline file gets its own retry entry', () async {
    final store = MemoryOfflineQueueStore();
    final api = FarmerApi(
      client: FakeClient((_) async => throw const SocketException('offline')),
      offlineQueue: OfflineQueue(store: store),
    )..queueUserId = 'user-a';
    final files = [
      XFile(
        (await File(
          '${Directory.systemTemp.path}/one.jpg',
        ).writeAsBytes([0xff, 0xd8, 0xff, 0xe0])).path,
      ),
      XFile(
        (await File(
          '${Directory.systemTemp.path}/two.jpg',
        ).writeAsBytes([0xff, 0xd8, 0xff, 0xe1])).path,
      ),
    ];

    await expectLater(
      api.uploadAttachments(
        parentType: 'task',
        parentId: 'task-1',
        files: files,
      ),
      throwsA(isA<OfflineQueuedException>()),
    );

    final queued = await OfflineQueue(store: store).entriesForUser('user-a');
    expect(queued.map((e) => e.body?['filename']), ['one.jpg', 'two.jpg']);
  });

  test(
    'attachment retry replays only the attachment and removes it on success',
    () async {
      final store = MemoryOfflineQueueStore();
      final queue = OfflineQueue(store: store);
      await queue.enqueue(
        OfflineQueueEntry(
          id: 'attachment-q',
          userId: 'user-a',
          method: 'POST',
          path: '/attachments',
          body: {
            'parentType': 'task',
            'parentId': 'task-1',
            'filename': 'field.jpg',
            'contentType': 'image/jpeg',
            'bytesBase64': base64Encode([0xff, 0xd8, 0xff, 0xe0]),
          },
          idempotencyKey: 'attachment-idem',
          createdAt: DateTime.utc(2026),
        ),
      );
      final requests = <http.BaseRequest>[];
      final api = FarmerApi(
        client: FakeClient((request) async {
          requests.add(request);
          return response(
            201,
            '{"id":"a1","parentType":"task","parentId":"task-1","contentType":"image/jpeg","sizeBytes":4,"createdAt":"2026-01-01T00:00:00Z","contentUrl":"/api/v1/attachments/a1/content"}',
          );
        }),
      )..token = 'token-a';

      await queue.flush('user-a', api.replayQueued);

      expect(requests, hasLength(1));
      expect(requests.single, isA<http.MultipartRequest>());
      expect((await queue.entriesForUser('user-a')), isEmpty);
    },
  );
}

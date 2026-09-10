import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:farmer/services/offline_queue.dart';

OfflineQueueEntry entry(String user, {String id = 'q1'}) => OfflineQueueEntry(
  id: id,
  userId: user,
  method: 'POST',
  path: '/tasks',
  body: {'name': 'x'},
  idempotencyKey: 'idem-$id',
  createdAt: DateTime.utc(2026, 1, 1),
);

void main() {
  test('queue entries encode and decode', () {
    final decoded = OfflineQueueEntry.fromJson(entry('a').toJson());
    expect(decoded.userId, 'a');
    expect(decoded.body, {'name': 'x'});
    expect(decoded.idempotencyKey, 'idem-q1');
  });

  test('entries are isolated by authenticated user', () async {
    final q = OfflineQueue(store: MemoryOfflineQueueStore());
    await q.enqueue(entry('a'));
    await q.enqueue(entry('b', id: 'q2'));
    expect((await q.entriesForUser('a')).map((e) => e.id), ['q1']);
    expect((await q.entriesForUser('b')).map((e) => e.id), ['q2']);
  });

  test('successful replay removes only the replayed entry', () async {
    final q = OfflineQueue(store: MemoryOfflineQueueStore());
    await q.enqueue(entry('a'));
    await q.enqueue(entry('b', id: 'q2'));
    await q.flush('a', (_) async {});
    expect((await q.entriesForUser('a')), isEmpty);
    expect((await q.entriesForUser('b')).single.id, 'q2');
  });

  test('enqueue during replay is preserved', () async {
    final q = OfflineQueue(store: MemoryOfflineQueueStore());
    await q.enqueue(entry('a'));
    final replayStarted = Completer<void>();
    final releaseReplay = Completer<void>();
    final flushFuture = q.flush('a', (_) async {
      replayStarted.complete();
      await releaseReplay.future;
    });
    await replayStarted.future;
    final enqueueFuture = q.enqueue(entry('a', id: 'q2'));
    releaseReplay.complete();
    await Future.wait([flushFuture, enqueueFuture]);
    expect((await q.entriesForUser('a')).map((e) => e.id), ['q2']);
  });

  test(
    'transport failure remains retryable and HTTP failure is retained blocked',
    () async {
      final q = OfflineQueue(store: MemoryOfflineQueueStore());
      await q.enqueue(entry('a'));
      var calls = 0;
      await q.flush('a', (_) async {
        calls++;
        throw Exception('network down');
      });
      expect(calls, 1);
      expect((await q.entriesForUser('a')).single.status, 'pending');
      await q.flush('a', (_) async {
        throw Exception('HTTP 422 validation');
      });
      expect((await q.entriesForUser('a')).single.status, 'blocked');
    },
  );
}

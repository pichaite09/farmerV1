import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'farmer_api.dart';
import 'push_service_types.dart';

abstract class BrowserPushService {
  bool get supported;
  Future<PushServiceStatus> status();
  Future<PushServiceStatus> enable(FarmerApi api);
  Future<void> disable(FarmerApi api);
}

BrowserPushService createBrowserPushService() => _WebBrowserPushService();

class _WebBrowserPushService implements BrowserPushService {
  static const _script = '/push_service_worker.js';
  static const _scope = '/push/';
  static const _subscriptionIdKey = 'farmer_push_subscription_id';

  @override
  bool get supported => true;

  Future<web.ServiceWorkerRegistration> _registration() => web
      .window
      .navigator
      .serviceWorker
      .register(_script, web.RegistrationOptions(scope: _scope))
      .toDart;

  Future<web.PushSubscription?> _subscription() async =>
      (await _registration()).pushManager.getSubscription().toDart;

  @override
  Future<PushServiceStatus> status() async {
    final subscription = await _subscription();
    return PushServiceStatus(
      supported: true,
      enabled: subscription != null,
      endpoint: subscription?.endpoint,
    );
  }

  @override
  Future<PushServiceStatus> enable(FarmerApi api) async {
    final permission =
        (await web.Notification.requestPermission().toDart).toDart;
    if (permission != 'granted') {
      throw StateError(
        permission == 'denied'
            ? 'การแจ้งเตือนถูกปฏิเสธ กรุณาอนุญาตในการตั้งค่าเบราว์เซอร์'
            : 'ยังไม่ได้อนุญาตการแจ้งเตือน',
      );
    }
    final registration = await _registration();
    var subscription = await registration.pushManager.getSubscription().toDart;
    if (subscription == null) {
      final key = (await api.vapidPublicKey())['publicKey'];
      if (key is! String || key.isEmpty) {
        throw StateError('API ไม่ส่งคีย์ Web Push');
      }
      final options = web.PushSubscriptionOptionsInit(
        userVisibleOnly: true,
        applicationServerKey: _decodeBase64Url(key).toJS,
      );
      subscription = await registration.pushManager.subscribe(options).toDart;
    }
    final payload = _payload(subscription);
    try {
      final saved = await api.registerPushSubscription(payload.toJson());
      final id = saved['id'];
      if (id is String) {
        web.window.localStorage.setItem(_subscriptionIdKey, id);
      }
    } catch (_) {
      await subscription.unsubscribe().toDart;
      rethrow;
    }
    return PushServiceStatus(
      supported: true,
      enabled: true,
      endpoint: payload.endpoint,
    );
  }

  @override
  Future<void> disable(FarmerApi api) async {
    final subscription = await _subscription();
    final id = web.window.localStorage.getItem(_subscriptionIdKey);
    if (id != null) {
      try {
        await api.deletePushSubscription(id);
      } finally {
        web.window.localStorage.removeItem(_subscriptionIdKey);
      }
    }
    if (subscription != null) await subscription.unsubscribe().toDart;
  }

  PushSubscriptionPayload _payload(web.PushSubscription subscription) {
    final p256dh = subscription.getKey('p256dh');
    final auth = subscription.getKey('auth');
    if (p256dh == null || auth == null) {
      throw StateError('เบราว์เซอร์ส่งคีย์ Web Push ไม่ครบ');
    }
    return PushSubscriptionPayload(
      endpoint: subscription.endpoint,
      p256dh: _base64Url(p256dh.toDart),
      auth: _base64Url(auth.toDart),
    );
  }

  String _base64Url(ByteBuffer value) => base64UrlEncode(value.asUint8List());

  Uint8List _decodeBase64Url(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    return Uint8List.fromList(
      base64.decode(
        normalized.padRight(
          normalized.length + (4 - normalized.length % 4) % 4,
          '=',
        ),
      ),
    );
  }
}

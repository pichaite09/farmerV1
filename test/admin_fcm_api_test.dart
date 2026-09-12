import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:farmer/models/admin_models.dart';
import 'package:farmer/services/farmer_api.dart';

class _CaptureClient extends http.BaseClient {
  late http.BaseRequest request;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest value) async {
    request = value;
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'targetUserId': 'user-1',
            'attempted': 2,
            'sent': 2,
            'failed': 0,
            'results': [
              {'deviceId': 'device-1', 'status': 'sent'},
              {'deviceId': 'device-2', 'status': 'sent'},
            ],
          }),
        ),
      ),
      200,
      request: value,
    );
  }
}

class _ImageClient extends http.BaseClient {
  late http.BaseRequest request;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest value) async {
    request = value;
    return http.StreamedResponse(
      Stream.value([1, 2, 3]),
      200,
      request: value,
      headers: {'content-type': 'image/png'},
    );
  }
}

void main() {
  test(
    'admin test notification API method is typed and sends contract',
    () async {
      final client = _CaptureClient();
      final result =
          await FarmerApi(
            baseUrl: 'https://staging.invalid',
            client: client,
          ).adminSendTestNotification(
            userId: 'user-1',
            title: 'หัวข้อ',
            body: 'ข้อความ',
          );
      expect(result, isA<AdminTestNotificationResult>());
      expect(result.attempted, 2);
      expect(result.sent, 2);
      expect(result.results.first.deviceId, 'device-1');
      expect(
        client.request.url.path,
        '/api/v1/admin/users/user-1/test-notification',
      );
      expect(jsonDecode((client.request as http.Request).body), {
        'title': 'หัวข้อ',
        'body': 'ข้อความ',
      });
    },
  );

  test(
    'announcement model keeps typed image metadata and authenticated image bytes use private endpoint',
    () async {
      final model = AdminAnnouncement.fromJson({
        'id': 'a1',
        'title': 'แจ้ง',
        'body': 'ข้อความ',
        'type': 'urgent',
        'targetType': 'all',
        'targetCount': 2,
        'announcementImageId': 'img-1',
      });
      expect(model.type, 'urgent');
      expect(model.imageId, 'img-1');
      final client = _ImageClient();
      final api = FarmerApi(baseUrl: 'https://staging.invalid', client: client)
        ..token = 'session-token';
      final bytes = await api.notificationImageBytes('notification-1');
      expect(bytes, [1, 2, 3]);
      expect(
        client.request.url.path,
        '/api/v1/notifications/notification-1/image',
      );
      expect(
        (client.request as http.Request).headers['authorization'],
        'Bearer session-token',
      );
    },
  );
}

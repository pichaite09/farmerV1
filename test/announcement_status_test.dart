import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmer/screens/admin_screen.dart';
import 'package:farmer/services/farmer_api.dart';
import 'package:farmer/models/admin_models.dart';

class AnnouncementApi extends FarmerApi {
  @override
  Future<List<AdminAnnouncement>> adminAnnouncements() async => [
    for (final status in [
      'draft',
      'queued',
      'sending',
      'sent',
      'completed',
      'cancelled',
    ])
      AdminAnnouncement.fromJson({
        'id': status,
        'title': 'notice-$status',
        'body': 'fixture',
        'status': status,
        'targetType': 'all',
        'targetCount': 1,
      }),
  ];
}

void main() {
  testWidgets('announcement labels and sent filter reflect delivery state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminAnnouncementsPage(api: AnnouncementApi()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'รอส่ง',
      'กำลังส่ง',
      'สิ้นสุดโดยไม่มี Push สำเร็จ',
      'ยกเลิกแล้ว',
    ]) {
      expect(find.textContaining('$label  •'), findsOneWidget);
    }
    await tester.tap(find.text('ส่งแล้ว'));
    await tester.pumpAndSettle();
    expect(find.text('notice-sent'), findsOneWidget);
    for (final status in [
      'draft',
      'queued',
      'sending',
      'completed',
      'cancelled',
    ]) {
      expect(find.text('notice-$status'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}

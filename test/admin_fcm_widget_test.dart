import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmer/screens/admin_screen.dart';
import 'support/admin_fixture_api.dart';

void main() {
  testWidgets('ผู้ดูแลส่งข้อความทดสอบจากรายการผู้ใช้งานได้', (tester) async {
    final api = AdminFixtureApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminUsersPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ส่งข้อความทดสอบ'), findsOneWidget);
    await tester.tap(find.text('ส่งข้อความทดสอบ').first);
    await tester.pumpAndSettle();
    expect(find.text('ส่งข้อความทดสอบ'), findsAtLeastNWidgets(1));
    expect(find.text('ยกเลิก'), findsOneWidget);
    expect(find.text('ส่ง'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'ทดสอบระบบ');
    await tester.enterText(fields.at(2), 'ข้อความแจ้งเตือนทดสอบ');
    await tester.tap(find.text('ส่ง'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.testNotificationCalled, isTrue);
    expect(find.text('ส่งข้อความทดสอบสำเร็จ'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:farmer/main.dart';
import 'package:farmer/services/api_session.dart';
import 'package:farmer/services/farmer_api.dart';
import 'package:farmer/providers/category_provider.dart';
import 'package:farmer/screens/auth_screen.dart';
import 'package:farmer/screens/plots_screen.dart';
import 'package:farmer/screens/cycles_screen.dart';
import 'package:farmer/screens/activities_screen.dart';
import 'package:farmer/screens/admin_screen.dart';
import 'package:farmer/models/api_models.dart';

void main() {
  testWidgets('แสดงหน้าล็อกอินเมื่อยังไม่มี session', (
    WidgetTester tester,
  ) async {
    final session = ApiSession()..initialized = true;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: session, child: const FarmerApp()),
    );
    await tester.pump();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('เข้าสู่ระบบ'), findsNWidgets(2));
  });

  testWidgets('เปิดฟอร์มแปลงและแสดง validation เมื่อบันทึกข้อมูลว่าง', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PlotFormDialog())),
    );
    await tester.tap(find.text('บันทึก'));
    await tester.pump();
    expect(find.text('กรุณากรอกชื่อแปลง'), findsOneWidget);
    expect(find.text('กรุณากรอกพื้นที่มากกว่า 0'), findsOneWidget);
  });

  testWidgets('เปิดฟอร์มรอบผลิตและ validation ต้องเลือกแปลง', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CategoryProvider(ApiSession()),
        child: const MaterialApp(
          home: Scaffold(body: CycleFormDialog(plots: [])),
        ),
      ),
    );
    await tester.tap(find.text('บันทึก'));
    await tester.pump();
    expect(find.text('กรุณาเลือกแปลง'), findsOneWidget);
  });

  testWidgets('routes admin sessions to the admin UI', (tester) async {
    final session = ApiSession()..initialized = true;
    session.api.token = 'test-token';
    session.user = const ApiUser(
      id: 'admin-1',
      email: 'admin@example.com',
      role: 'admin',
      status: 'active',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: session, child: const FarmerApp()),
    );
    await tester.pump();
    expect(find.byType(AdminScreen), findsOneWidget);
    expect(find.text('ศูนย์จัดการระบบ'), findsOneWidget);
    expect(find.text('ภาพรวม'), findsOneWidget);
    expect(find.text('ผู้ใช้งาน'), findsOneWidget);
  });

  testWidgets('admin navigation exposes all MVP sections', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminScreen(api: FarmerApi())));
    await tester.pump();
    expect(find.text('ภาพรวม'), findsOneWidget);
    expect(find.text('ผู้ใช้งาน'), findsOneWidget);
    expect(find.text('ข้อมูลเกษตร'), findsOneWidget);
    expect(find.text('ประกาศ'), findsOneWidget);
    expect(find.text('บันทึกกิจกรรม'), findsOneWidget);
  });
  testWidgets('announcement actions stack on narrow screens', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 800));
    await tester.pumpWidget(
      MaterialApp(home: AdminAnnouncementsPage(api: FarmerApi())),
    );
    await tester.pump();
    expect(find.text('สร้างประกาศ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ฟอร์มกิจกรรมมีตัวเลือกเก็บเกี่ยว', (tester) async {
    final cycle = ProductionCycle(
      id: 'c1',
      name: 'รอบ 1',
      plotId: 'p1',
      plotName: 'แปลง 1',
      cropType: 'ข้าว',
      variety: 'กข6',
      plantingMethod: 'หว่าน',
      startDate: DateTime(2026),
      status: 'active',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CategoryProvider(ApiSession()),
        child: MaterialApp(
          home: Scaffold(body: ActivityFormDialog(cycles: [cycle])),
        ),
      ),
    );
    expect(
      find.text('กิจกรรมนี้คือการเก็บเกี่ยวและปิดรอบผลิต'),
      findsOneWidget,
    );
    expect(find.textContaining('completeCycle=true'), findsNothing);
  });
}

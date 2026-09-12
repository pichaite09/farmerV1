import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmer/screens/admin_screen.dart';
import 'support/admin_fixture_api.dart';

void main() {
  testWidgets('desktop records table shows all seven typed details', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(home: AdminScreen(api: AdminFixtureApi())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ข้อมูลเกษตร').first);
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.getTopLeft(find.text('ADMIN OPERATIONS')).dy, lessThan(100));
    for (var i = 0; i < 7; i++) {
      final rows = tester.widget<DataTable>(find.byType(DataTable)).rows;
      rows[i].onSelectChanged!(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('ผู้บันทึก: สมชาย เกษตรดี'), findsOneWidget);
      expect(find.textContaining('synthetic-'), findsNothing);
      await tester.tap(find.text('ปิด'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  for (final width in [1440.0, 390.0]) {
    testWidgets('overview first, scoped dark readable top aligned at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: AdminScreen(api: AdminFixtureApi()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboardPage), findsOneWidget);
      if (width == 390) {
        final cards = find.byType(Card);
        expect(
          tester.getTopLeft(cards.at(0)).dy,
          tester.getTopLeft(cards.at(1)).dy,
        );
      }
      expect(
        tester.getTopLeft(find.text('ADMIN OPERATIONS')).dy,
        lessThan(100),
      );
      final theme = Theme.of(tester.element(find.text('ภาพรวมระบบ')));
      expect(theme.brightness, Brightness.dark);
      expect(
        theme.textTheme.bodyMedium!.color!.computeLuminance(),
        greaterThan(.5),
      );
      expect(
        theme.navigationBarTheme.backgroundColor?.computeLuminance() ??
            theme.colorScheme.surface.computeLuminance(),
        lessThan(.1),
      );
      expect(find.text('API พร้อมใช้งาน'), findsNothing);
      final labels = width > 900
          ? tester
                .widgetList<ListTile>(find.byType(ListTile))
                .map((w) => (w.title as Text).data)
                .toList()
          : tester
                .widgetList<NavigationDestination>(
                  find.byType(NavigationDestination),
                )
                .map((w) => w.label)
                .toList();
      expect(labels, [
        'ภาพรวม',
        'ข้อมูลเกษตร',
        'ผู้ใช้งาน',
        'ประกาศ',
        'บันทึกกิจกรรม',
      ]);
      await tester.tap(find.text('ผู้ใช้งาน').first);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'records default all composes farmer and opens typed safe detail',
    (tester) async {
      final api = AdminFixtureApi();
      await tester.pumpWidget(MaterialApp(home: AdminScreen(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ข้อมูลเกษตร').first);
      await tester.pumpAndSettle();
      expect(api.requestedType, 'all');
      expect(api.requestedOwner, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String?>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('สมชาย เกษตรดี').last);
      await tester.pumpAndSettle();
      expect(api.requestedType, 'all');
      expect(api.requestedOwner, 'synthetic-farmer');
      expect(api.requestedOffset, 0);
      await tester.tap(find.text('ปลูกข้าวฤดูฝน'));
      await tester.pumpAndSettle();
      expect(find.text('รูปภาพ 1 รายการ'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(find.byType(InkWell), findsWidgets);
      expect(find.textContaining('ผู้บันทึก: สมชาย เกษตรดี'), findsOneWidget);
      expect(find.textContaining('11 ก.ย. 2569'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'production cycle detail shows summary timeline and disjoint filters',
    (tester) async {
      final api = AdminFixtureApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminProductionCycleDetailPage(
              api: api,
              cycleId: 'synthetic-production_cycle',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('กิจกรรม 1'), findsOneWidget);
      expect(find.text('ตรวจแปลง 1'), findsOneWidget);
      expect(find.text('กรองประเภทในไทม์ไลน์'), findsOneWidget);
      expect(find.text('ปลูกข้าวฤดูฝน'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('งาน').last);
      await tester.pumpAndSettle();
      expect(find.text('งาน 1'), findsOneWidget);
      expect(find.text('ปลูกข้าวฤดูฝน'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('production cycle detail remains usable on narrow layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminProductionCycleDetailPage(
            api: AdminFixtureApi(),
            cycleId: 'synthetic-production_cycle',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('แปลงนาข้าวตัวอย่าง'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('production cycle detail dialog is narrow safe', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminRecordsPage(api: AdminFixtureApi())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('รอบผลิต').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('แปลงนาข้าวตัวอย่าง').last);
    await tester.pumpAndSettle();
    final dialogWidth = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byType(AdminProductionCycleDetailPage),
        matching: find.byType(SizedBox),
      ).first,
    ).width;
    expect(dialogWidth, lessThanOrEqualTo(390));
    expect(find.text('ปลูกข้าวฤดูฝน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

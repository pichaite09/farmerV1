import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('work navigation tabs fit narrow and large text layouts', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 360.0, 390.0, 768.0, 1440.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        await tester.binding.setSurfaceSize(Size(width, 120));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 120),
                textScaler: TextScaler.linear(scale),
              ),
              child: const DefaultTabController(
                length: 5,
                child: Scaffold(
                  body: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'กิจกรรม'),
                      Tab(text: 'ตรวจแปลง'),
                      Tab(text: 'ตารางงาน'),
                      Tab(text: 'รอบผลิต'),
                      Tab(text: 'แปลงเกษตร'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$width px at $scale text scale',
        );
      }
    }
  });
}

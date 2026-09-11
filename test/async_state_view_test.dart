import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmer/widgets/async_state_view.dart';

void main() {
  testWidgets('shows loading, error with retry, and empty states', (
    tester,
  ) async {
    final retry = ValueNotifier<int>(0);
    Future<String> future() async {
      if (retry.value == 0) throw StateError('network');
      return '';
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: retry,
          builder: (_, __, ___) => AsyncStateView<String>(
            future: future(),
            empty: const Text('ไม่มีข้อมูล'),
            isEmpty: (value) => value.isEmpty,
            onRetry: () => retry.value++,
            builder: (_, value) => Text(value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('โหลดไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('ไม่มีข้อมูล'), findsOneWidget);
  });

  testWidgets('provides semantic labels for loading and retry actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncStateView<int>(
          future: Future<int>.value(1),
          builder: (_, value) => Text('$value'),
        ),
      ),
    );
    expect(find.bySemanticsLabel('กำลังโหลด'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });
}

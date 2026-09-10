import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_session.dart';
import '../providers/category_provider.dart';
import 'dashboard_screen.dart';
import 'work_screen.dart';
import 'finance_screen.dart';
import 'fuel_management_screen.dart';
import 'activities_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'field_inspections_screen.dart';
import 'notification_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int index = 0;
  int get pageIndex => index > 2 ? index - 1 : index;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CategoryProvider>().load();
    });
  }

  Future<void> _openAdd() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('เพิ่มรายการการเงิน'),
              onTap: () => Navigator.pop(context, 'finance'),
            ),
            ListTile(
              leading: const Icon(Icons.local_gas_station),
              title: const Text('เติมเชื้อเพลิง'),
              onTap: () => Navigator.pop(context, 'fuel'),
            ),
            ListTile(
              leading: const Icon(Icons.event_note),
              title: const Text('เพิ่มกิจกรรม'),
              onTap: () => Navigator.pop(context, 'activity'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('เพิ่มตารางงาน'),
              onTap: () => Navigator.pop(context, 'task'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check),
              title: const Text('เพิ่มการตรวจแปลง'),
              onTap: () => Navigator.pop(context, 'inspection'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'finance') await showNewTransactionDialog(context);
    if (choice == 'fuel') await showNewFuelDialog(context);
    if (choice == 'activity') await showNewActivityDialog(context);
    if (choice == 'task') await showNewTaskDialog(context);
    if (choice == 'inspection') await showNewFieldInspectionDialog(context);
  }

  final pages = const [
    DashboardScreen(),
    WorkScreen(),
    FinanceScreen(),
    FuelManagementScreen(),
  ];
  final titles = const ['หน้าแรก', 'งาน', 'การเงิน', 'จัดการเชื้อเพลิง'];
  Widget build(BuildContext c) {
    final session = c.watch<ApiSession>();
    return Scaffold(
      appBar: pageIndex == 0
          ? null
          : AppBar(
              title: Text(titles[pageIndex]),
              actions: [
                const NotificationBell(),
                if (session.pendingQueueCount > 0)
                  IconButton(
                    tooltip: 'ซิงค์รายการค้าง',
                    onPressed: session.syncOfflineQueue,
                    icon: const Icon(Icons.sync_problem),
                  ),
                IconButton(
                  tooltip: 'ออกจากระบบ',
                  onPressed: session.logout,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
      body: Column(
        children: [
          if (session.pendingQueueCount > 0)
            MaterialBanner(
              content: Text(
                session.blockedQueueCount > 0
                    ? 'มีรายการซิงค์ติดปัญหา ${session.blockedQueueCount} รายการ (ต้องแก้ไขแล้วลองใหม่)'
                    : 'มีรายการรอซิงค์ ${session.pendingQueueCount} รายการ',
              ),
              leading: const Icon(Icons.cloud_off),
              actions: [
                TextButton(
                  onPressed: session.syncOfflineQueue,
                  child: const Text('ซิงค์ตอนนี้'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(index: pageIndex, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          if (i == 2) {
            _openAdd();
          } else {
            setState(() => index = i);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'หน้าแรก',
          ),
          NavigationDestination(
            icon: Icon(Icons.agriculture_outlined),
            selectedIcon: Icon(Icons.agriculture),
            label: 'งาน',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'เพิ่มข้อมูล',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'การเงิน',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_gas_station_outlined),
            selectedIcon: Icon(Icons.local_gas_station),
            label: 'เชื้อเพลิง',
          ),
        ],
      ),
    );
  }
}

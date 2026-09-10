import 'package:flutter/material.dart';
import 'plots_screen.dart';
import 'cycles_screen.dart';
import 'activities_screen.dart';
import 'field_inspections_screen.dart';
import 'schedule_screen.dart';

class WorkScreen extends StatelessWidget {
  const WorkScreen({super.key});
  Widget build(BuildContext c) => DefaultTabController(
    length: 5,
    child: Column(
      children: [
        const TabBar(
          isScrollable: false,
          labelPadding: EdgeInsets.symmetric(horizontal: 4),
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontSize: 12),
          tabs: [
            Tab(text: 'กิจกรรม'),
            Tab(text: 'ตรวจแปลง'),
            Tab(text: 'ตารางงาน'),
            Tab(text: 'รอบผลิต'),
            Tab(text: 'แปลงเกษตร'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: const [
              ActivitiesScreen(),
              FieldInspectionsScreen(),
              ScheduleScreen(),
              CyclesScreen(),
              PlotsScreen(),
            ],
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import '../providers/category_provider.dart';
import 'activities_screen.dart';
import 'schedule_screen.dart';
import '../widgets/production_cycle_summary.dart';

String _taskStatusLabel(String status) => switch (status) {
  'pending' => 'รอดำเนินการ',
  'in_progress' => 'กำลังทำ',
  'completed' => 'เสร็จแล้ว',
  _ => status,
};

class CyclesScreen extends StatefulWidget {
  const CyclesScreen({super.key});
  @override
  State<CyclesScreen> createState() => _CyclesScreenState();
}

class _CyclesScreenState extends State<CyclesScreen> {
  late Future<List<ProductionCycle>> future;
  late Future<List<ProductionCycleSummary>> summaryFuture;
  List<Plot> plots = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<ApiSession>().api;
    future = api.cycles();
    summaryFuture = api.productionCycleSummaries();
    context.read<ApiSession>().api.plots().then((v) {
      if (mounted) setState(() => plots = v);
    });
  }

  void _reload() => setState(_load);
  Future<void> _form([ProductionCycle? cycle]) async {
    if (plots.isEmpty && cycle == null) {
      _msg('กรุณาสร้างแปลงเกษตรก่อน');
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => CycleFormDialog(cycle: cycle, plots: plots),
    );
    if (result == null || !mounted) return;
    try {
      final api = context.read<ApiSession>().api;
      if (cycle == null)
        await api.createCycle(result);
      else
        await api.updateCycle(cycle.id, result);
      _reload();
    } catch (e) {
      _msg(e.toString());
    }
  }

  Future<void> _delete(ProductionCycle c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบ "${c.name}" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await context.read<ApiSession>().api.deleteCycle(c.id);
      _reload();
    } catch (e) {
      _msg(e.toString());
    }
  }

  void _msg(String s) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ProductionCycle>>(
    future: future,
    builder: (c, s) {
      if (s.connectionState == ConnectionState.waiting)
        return const Center(child: CircularProgressIndicator());
      if (s.hasError) return Center(child: Text('${s.error}'));
      final xs = s.data ?? [];
      if (xs.isEmpty)
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync_alt, size: 72, color: Colors.grey),
              const Text('ยังไม่มีรอบการผลิต'),
              FilledButton.icon(
                onPressed: () => _form(),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มรอบการผลิต'),
              ),
            ],
          ),
        );
      return Scaffold(
        body: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'รอบการผลิต'),
                  Tab(text: 'สรุป'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: xs.length,
                      itemBuilder: (_, i) {
                        final x = xs[i];
                        final status = x.status == 'completed'
                            ? 'เก็บเกี่ยวเรียบร้อย'
                            : 'ดำเนินการอยู่';
                        return Card(
                          child: ListTile(
                            isThreeLine: true,
                            leading: Icon(
                              x.status == 'completed'
                                  ? Icons.check_circle
                                  : Icons.sync,
                              color: x.status == 'completed'
                                  ? Colors.grey
                                  : Colors.green,
                            ),
                            title: Text(
                              '${x.plotName} ${x.name}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${x.cropType}${x.variety.isEmpty ? '' : ' • สายพันธุ์ ${x.variety}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${x.plantingMethod} • เริ่ม ${DateFormat('dd/MM/yyyy').format(x.startDate)}',
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                                Text(status),
                              ],
                            ),
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => CycleActivitiesDialog(cycle: x),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit')
                                  _form(x);
                                else
                                  _delete(x);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('แก้ไข'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('ลบ'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    ProductionCycleSummaryView(
                      future: summaryFuture,
                      onRetry: _reload,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _form(),
          tooltip: 'เพิ่มรอบการผลิต',
          child: const Icon(Icons.add),
        ),
      );
    },
  );
}

class CycleActivitiesDialog extends StatefulWidget {
  final ProductionCycle cycle;
  const CycleActivitiesDialog({super.key, required this.cycle});
  @override
  State<CycleActivitiesDialog> createState() => _CycleActivitiesDialogState();
}

class _CycleActivitiesDialogState extends State<CycleActivitiesDialog> {
  late Future<List<Activity>> future;
  late Future<List<FarmerTask>> tasksFuture;
  late Future<List<FieldInspection>> inspectionsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<ApiSession>().api;
    future = api.activities(cycleId: widget.cycle.id);
    tasksFuture = api.tasks(cycleId: widget.cycle.id);
    inspectionsFuture = api.fieldInspections(cycleId: widget.cycle.id);
  }

  Future<void> _add() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ActivityFormDialog(cycles: [widget.cycle]),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<ApiSession>().api.createActivity({
        ...result,
        'cycleId': widget.cycle.id,
      });
      setState(_load);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เพิ่มกิจกรรมไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _addTask() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TaskDialog(cycles: [widget.cycle]),
    );
    if (result == true && mounted) setState(_load);
  }

  Widget _timelineList() => FutureBuilder<List<dynamic>>(
    future: Future.wait<dynamic>([future, tasksFuture, inspectionsFuture]),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError)
        return Text('โหลดข้อมูลรอบผลิตไม่สำเร็จ: ${snapshot.error}');
      final activities = snapshot.data![0] as List<Activity>;
      final tasks = snapshot.data![1] as List<FarmerTask>;
      final inspections = snapshot.data![2] as List<FieldInspection>;
      final items =
          <Map<String, dynamic>>[
            ...activities.map((x) => {'date': x.date, 'activity': x}),
            ...tasks.map((x) => {'date': x.dueDate, 'task': x}),
            ...inspections.map(
              (x) => {'date': x.inspectionDate, 'inspection': x},
            ),
          ]..sort(
            (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
          );
      if (items.isEmpty)
        return const Center(
          child: Text('ยังไม่มีกิจกรรม ตรวจแปลง หรือตารางงานในรอบนี้'),
        );
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          final activity = item['activity'] as Activity?;
          final task = item['task'] as FarmerTask?;
          final inspection = item['inspection'] as FieldInspection?;
          if (inspection != null) {
            final status = switch (inspection.overallStatus) {
              'good' => 'ปกติ',
              'attention' => 'เฝ้าระวัง',
              'critical' => 'พบปัญหา',
              _ => inspection.overallStatus,
            };
            final followUp = inspection.followUpTaskId == null
                ? ''
                : ' • ติดตามผล: ${inspection.followUpStatus == 'completed' ? 'เสร็จแล้ว' : 'รอดำเนินการ'}';
            return ListTile(
              dense: true,
              leading: Icon(
                Icons.fact_check,
                color: inspection.overallStatus == 'critical'
                    ? Colors.red
                    : Colors.orange,
              ),
              title: const Text('ตรวจแปลง'),
              subtitle: Text(
                '${DateFormat('dd/MM/yyyy').format(inspection.inspectionDate)} • สถานะ: $status$followUp${inspection.notes == null || inspection.notes!.isEmpty ? '' : ' • ${inspection.notes}'}',
              ),
            );
          }
          if (activity != null) {
            return ListTile(
              dense: true,
              leading: const Icon(Icons.task_alt, color: Colors.green),
              title: Text('กิจกรรม: ${activity.type}'),
              subtitle: Text(
                '${DateFormat('dd/MM/yyyy').format(activity.date)}${activity.description == null || activity.description!.isEmpty ? '' : ' • ${activity.description}'}',
              ),
            );
          }
          return ListTile(
            dense: true,
            leading: Icon(
              task!.status == 'completed'
                  ? Icons.check_circle
                  : Icons.event_note,
            ),
            title: Text(
              '${task.isAutomaticFollowUp ? 'ติดตามผลอัตโนมัติ' : 'ตารางงาน'}: ${task.name}',
            ),
            subtitle: Text(
              '${DateFormat('dd/MM/yyyy').format(task.dueDate)} • สถานะ: ${_taskStatusLabel(task.status)}${task.description == null || task.description!.isEmpty ? '' : ' • ${task.description}'}',
            ),
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('รอบผลิต: ${widget.cycle.name}'),
    content: SizedBox(width: 460, height: 390, child: _timelineList()),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ปิด'),
      ),
      OutlinedButton.icon(
        onPressed: widget.cycle.status == 'completed' ? null : _add,
        icon: const Icon(Icons.add_task),
        label: const Text('เพิ่มกิจกรรม'),
      ),
      FilledButton.icon(
        onPressed: widget.cycle.status == 'completed' ? null : _addTask,
        icon: const Icon(Icons.event_available),
        label: const Text('เพิ่มตารางงาน'),
      ),
    ],
  );
}

class CycleFormDialog extends StatefulWidget {
  final ProductionCycle? cycle;
  final List<Plot> plots;
  const CycleFormDialog({this.cycle, required this.plots});
  @override
  State<CycleFormDialog> createState() => CycleFormDialogState();
}

class CycleFormDialogState extends State<CycleFormDialog> {
  final key = GlobalKey<FormState>();
  late final TextEditingController name, crop, variety, method;
  String? plotId, status;
  late DateTime date;
  @override
  void initState() {
    super.initState();
    final x = widget.cycle;
    name = TextEditingController(text: x?.name);
    crop = TextEditingController(text: x?.cropType);
    variety = TextEditingController(text: x?.variety);
    method = TextEditingController(text: x?.plantingMethod);
    plotId = x?.plotId ?? (widget.plots.isEmpty ? null : widget.plots.first.id);
    status = x?.status.isNotEmpty == true ? x!.status : 'active';
    date = x?.startDate ?? DateTime.now();
  }

  @override
  void dispose() {
    name.dispose();
    crop.dispose();
    variety.dispose();
    method.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final x = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (x != null) setState(() => date = x);
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(widget.cycle == null ? 'เพิ่มรอบการผลิต' : 'แก้ไขรอบการผลิต'),
    content: Form(
      key: key,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'ชื่อรอบการผลิต'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'กรุณากรอกชื่อรอบการผลิต'
                  : null,
            ),
            DropdownButtonFormField<String>(
              value: plotId,
              decoration: const InputDecoration(labelText: 'เลือกแปลง'),
              items: widget.plots
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => plotId = v),
              validator: (v) => v == null ? 'กรุณาเลือกแปลง' : null,
            ),
            Builder(
              builder: (context) {
                final cats = context.watch<CategoryProvider>();
                final crops = cats.cropTypes;
                final methods = cats.plantingTypes;
                return Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: crops.contains(crop.text) ? crop.text : null,
                      decoration: const InputDecoration(labelText: 'พืชเกษตร'),
                      items: crops
                          .map(
                            (x) => DropdownMenuItem(value: x, child: Text(x)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => crop.text = v ?? ''),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'กรุณาเลือกพืชเกษตร' : null,
                    ),
                    TextFormField(
                      controller: variety,
                      decoration: const InputDecoration(labelText: 'สายพันธุ์'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'กรุณากรอกสายพันธุ์'
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      value: methods.contains(method.text) ? method.text : null,
                      decoration: const InputDecoration(
                        labelText: 'วิธีการปลูก',
                      ),
                      items: methods
                          .map(
                            (x) => DropdownMenuItem(value: x, child: Text(x)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => method.text = v ?? ''),
                      validator: (v) => v == null || v.isEmpty
                          ? 'กรุณาเลือกวิธีการปลูก'
                          : null,
                    ),
                  ],
                );
              },
            ),
            DropdownButtonFormField<String>(
              value: status,
              decoration: const InputDecoration(labelText: 'สถานะ'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('ดำเนินการอยู่')),
                DropdownMenuItem(
                  value: 'completed',
                  child: Text('เก็บเกี่ยวเรียบร้อย'),
                ),
              ],
              onChanged: (v) => setState(() => status = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'วันเริ่มต้น: ${DateFormat('dd/MM/yyyy').format(date)}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: pick,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () {
          if (key.currentState!.validate())
            Navigator.pop(c, {
              'name': name.text.trim(),
              'plotId': plotId,
              'cropType': crop.text.trim(),
              'variety': variety.text.trim(),
              'plantingMethod': method.text.trim(),
              'startDate': date.toIso8601String(),
              'status': status ?? 'active',
            });
        },
        child: const Text('บันทึก'),
      ),
    ],
  );
}

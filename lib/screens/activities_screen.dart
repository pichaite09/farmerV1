import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/thai_date.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import '../widgets/attachment_thumbnail.dart';
import '../providers/category_provider.dart';

Future<bool?> showNewActivityDialog(BuildContext context) async {
  final api = context.read<ApiSession>().api;
  final cycles = await api.cycles();
  if (!context.mounted) return false;
  if (cycles.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('กรุณาสร้างรอบการผลิตก่อน')));
    return false;
  }
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => ActivityFormDialog(cycles: cycles),
  );
  if (result == null || !context.mounted) return false;
  await api.createActivity(result);
  return true;
}

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});
  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  late Future<List<Activity>> future;
  List<ProductionCycle> cycles = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    future = context.read<ApiSession>().api.activities();
    context.read<ApiSession>().api.cycles().then((v) {
      if (mounted) setState(() => cycles = v);
    });
  }

  void _reload() => setState(_load);
  Future<void> _form([Activity? activity]) async {
    if (cycles.isEmpty && activity == null) {
      _msg('กรุณาสร้างรอบการผลิตก่อน');
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ActivityFormDialog(activity: activity, cycles: cycles),
    );
    if (result == null || !mounted) return;
    try {
      final api = context.read<ApiSession>().api;
      if (activity == null)
        await api.createActivity(result);
      else
        await api.updateActivity(activity.id, result);
      _reload();
    } catch (e) {
      _msg(e.toString());
    }
  }

  Future<void> _delete(Activity x) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: const Text('ต้องการลบกิจกรรมนี้หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await context.read<ApiSession>().api.deleteActivity(x.id);
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
  Widget build(BuildContext context) => FutureBuilder<List<Activity>>(
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
              const Icon(Icons.task_alt, size: 72, color: Colors.grey),
              const Text('ยังไม่มีกิจกรรมที่บันทึกไว้'),
              FilledButton.icon(
                onPressed: () => _form(),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มกิจกรรม'),
              ),
            ],
          ),
        );
      return Scaffold(
        body: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: xs.length,
          itemBuilder: (_, i) {
            final x = xs[i];
            final cycle = cycles.where((c) => c.id == x.cycleId).firstOrNull;
            return Card(
              child: ListTile(
                leading: AttachmentThumbnail(
                  parentType: 'activity',
                  parentId: x.id,
                ),
                title: Text(
                  x.type,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${x.description ?? ''}\n${cycle == null ? 'ไม่ระบุแปลง • ไม่ระบุรอบ' : '${cycle.plotName} • ${cycle.name}'} • ${ThaiDate.format(x.date)}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit')
                      _form(x);
                    else
                      _delete(x);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                    PopupMenuItem(value: 'delete', child: Text('ลบ')),
                  ],
                ),
                onTap: () => _imageAction(x),
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _form(),
          tooltip: 'เพิ่มกิจกรรม',
          child: const Icon(Icons.add),
        ),
      );
    },
  );

  Future<void> _imageAction(Activity activity) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 800,
    );
    if (file == null || !mounted) return;
    try {
      final api = context.read<ApiSession>().api;
      final attachment = await api.uploadAttachment(
        parentType: 'activity',
        parentId: activity.id,
        file: file,
      );
      final bytes = await api.attachmentContent(attachment.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          content: Image.memory(bytes, fit: BoxFit.contain),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
      _reload();
    } catch (e) {
      _msg('อัปโหลด/โหลดรูปภาพไม่สำเร็จ (รูปภาพไม่ถูกเข้าคิว): $e');
    }
  }
}

class ActivityFormDialog extends StatefulWidget {
  final Activity? activity;
  final List<ProductionCycle> cycles;
  const ActivityFormDialog({this.activity, required this.cycles});
  @override
  State<ActivityFormDialog> createState() => ActivityFormDialogState();
}

class ActivityFormDialogState extends State<ActivityFormDialog> {
  final key = GlobalKey<FormState>();
  late final TextEditingController type, description;
  String? cycleId;
  late DateTime date;
  bool harvest = false;
  @override
  void initState() {
    super.initState();
    final x = widget.activity;
    type = TextEditingController(text: x?.type);
    description = TextEditingController(text: x?.description);
    cycleId =
        x?.cycleId ?? (widget.cycles.isEmpty ? null : widget.cycles.first.id);
    date = x?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    type.dispose();
    description.dispose();
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
    title: Text(widget.activity == null ? 'เพิ่มกิจกรรม' : 'แก้ไขกิจกรรม'),
    content: Form(
      key: key,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: cycleId,
              decoration: const InputDecoration(labelText: 'เลือกรอบการผลิต'),
              items: widget.cycles
                  .map(
                    (x) => DropdownMenuItem(
                      value: x.id,
                      child: Text('${x.plotName} • ${x.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => cycleId = v),
              validator: (v) => v == null ? 'กรุณาเลือกรอบการผลิต' : null,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final values = context
                    .watch<CategoryProvider>()
                    .activityCategories;
                return DropdownButtonFormField<String>(
                  value: values.contains(type.text) ? type.text : null,
                  decoration: const InputDecoration(labelText: 'ประเภทกิจกรรม'),
                  items: values
                      .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                      .toList(),
                  onChanged: (v) => setState(() => type.text = v ?? ''),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'กรุณาเลือกประเภทกิจกรรม' : null,
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              decoration: const InputDecoration(labelText: 'คำอธิบาย'),
              maxLines: 3,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('วันที่: ${ThaiDate.format(date)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: pick,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('กิจกรรมนี้คือการเก็บเกี่ยวและปิดรอบผลิต'),
              subtitle: const Text(
                'เมื่อบันทึก ระบบจะเปลี่ยนสถานะรอบผลิตเป็นเก็บเกี่ยวเรียบร้อย',
              ),
              value: harvest,
              onChanged: (v) => setState(() => harvest = v ?? false),
            ),
            const Text(
              'แนบรูปภาพได้หลังบันทึกกิจกรรม (ออนไลน์เท่านั้น)',
              style: TextStyle(color: Colors.grey),
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
              'cycleId': cycleId,
              'type': type.text.trim(),
              'description': description.text.trim(),
              'date': date.toIso8601String(),
              'completeCycle': harvest,
            });
        },
        child: const Text('บันทึก'),
      ),
    ],
  );
}

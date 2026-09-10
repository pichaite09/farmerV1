import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import '../services/offline_queue.dart';

String _sd(DateTime d) => d.toIso8601String().split('T').first;
Future<bool> _sc(BuildContext c, String n) => showDialog<bool>(
  context: c,
  builder: (x) => AlertDialog(
    title: const Text('ยืนยันการลบ'),
    content: Text('ลบงาน "$n"?'),
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
).then((v) => v ?? false);

Future<bool?> showNewTaskDialog(BuildContext context) async {
  final cycles = await context.read<ApiSession>().api.cycles();
  if (!context.mounted) return false;
  if (cycles.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('กรุณาสร้างรอบการผลิตก่อนเพิ่มงาน')),
    );
    return false;
  }
  return showDialog<bool>(
    context: context,
    builder: (_) => TaskDialog(cycles: cycles),
  );
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleState();
}

class _ScheduleState extends State<ScheduleScreen> {
  late Future<List<FarmerTask>> f;
  late Future<List<ProductionCycle>> cf;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    f = context.read<ApiSession>().api.tasks();
    cf = context.read<ApiSession>().api.cycles();
  }

  void _refresh() => setState(_load);
  Future<void> _complete(FarmerTask task) async {
    final result = await _completionDialog(task);
    if (result == null || !mounted) return;
    final note = result['note'] as String;
    final files = result['files'] as List<XFile>;
    try {
      final payload = <String, dynamic>{'status': 'completed'};
      if (note.trim().isNotEmpty) payload['description'] = note.trim();
      await context.read<ApiSession>().api.updateTask(task.id, payload);
      var imageMessage = '';
      if (files.isNotEmpty) {
        try {
          await context.read<ApiSession>().api.uploadAttachments(
            parentType: 'task',
            parentId: task.id,
            files: files,
          );
          imageMessage = ' เพิ่มรูปแล้ว ${files.length} รูป';
        } catch (_) {
          imageMessage = ' แต่เพิ่มรูปไม่สำเร็จ';
        }
      }
      if (!mounted) return;
      _refresh();
      final message = task.isAutomaticFollowUp
          ? 'ปิดงานติดตามผลแล้ว และอัปเดตสถานะการตรวจแปลงแล้ว$imageMessage'
          : 'บันทึกสำเร็จแล้ว$imageMessage';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted && e is OfflineQueuedException) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'งานถูกบันทึกเข้าคิวแล้ว รูปภาพจะต้องแนบใหม่เมื่อออนไลน์',
            ),
          ),
        );
        _refresh();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
      }
    }
  }

  Future<Map<String, dynamic>?> _completionDialog(FarmerTask task) async {
    final controller = TextEditingController();
    final selected = <XFile>[];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('บันทึกผลการทำงาน'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${task.name}\nกรุณาระบุสิ่งที่ทำและแนบรูปประกอบได้'),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'ทำอะไรไป',
                    hintText: 'เช่น ใส่ปุ๋ยแปลงข้าวและตรวจระบบน้ำแล้ว',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final files = await ImagePicker().pickMultiImage(
                      imageQuality: 80,
                      maxWidth: 1600,
                    );
                    if (files.isNotEmpty) {
                      setDialogState(() => selected.addAll(files));
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('เพิ่มรูปภาพ'),
                ),
                if (selected.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('เลือกรูปแล้ว ${selected.length} รูป'),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (var i = 0; i < selected.length; i++)
                        Chip(
                          label: SizedBox(
                            width: 150,
                            child: Text(
                              selected[i].name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onDeleted: () =>
                              setDialogState(() => selected.removeAt(i)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop({
                'note': controller.text,
                'files': List<XFile>.from(selected),
              }),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _form(List<ProductionCycle> cs, {FarmerTask? task}) async {
    if (cs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาสร้างรอบการผลิตก่อนเพิ่มงาน')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => TaskDialog(task: task, cycles: cs),
    );
    if (ok == true) _refresh();
  }

  Widget _buildTaskList(BuildContext c) => FutureBuilder<List<ProductionCycle>>(
    future: cf,
    builder: (c, cs) {
      if (!cs.hasData) return const Center(child: CircularProgressIndicator());
      final names = {
        for (final x in cs.data!) x.id: '${x.plotName} • ${x.name}',
      };
      return FutureBuilder<List<FarmerTask>>(
        future: f,
        builder: (c, s) {
          if (s.hasError)
            return Center(child: Text('โหลดไม่สำเร็จ: ${s.error}'));
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          final xs = s.data!;
          return Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () => _form(cs.data!),
              tooltip: 'เพิ่มงาน',
              child: const Icon(Icons.add),
            ),
            body: xs.isEmpty
                ? const Center(child: Text('ยังไม่มีงาน'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: xs.length,
                    itemBuilder: (_, i) {
                      final x = xs[i];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            x.status == 'completed'
                                ? Icons.check_circle
                                : x.status == 'in_progress'
                                ? Icons.hourglass_bottom
                                : Icons.assignment_outlined,
                          ),
                          title: Text(x.name),
                          subtitle: Text(
                            '${names[x.cycleId] ?? 'ไม่พบรอบผลิต'} • ${_sd(x.dueDate)}${x.isAutomaticFollowUp ? '\nงานติดตามผลอัตโนมัติ' : ''}${x.description == null || x.description!.isEmpty ? '' : '\n${x.description}'}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (x.status != 'completed')
                                FilledButton.tonal(
                                  onPressed: () => _complete(x),
                                  child: const Text('สำเร็จ'),
                                ),
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'edit') _form(cs.data!, task: x);
                                  if (v == 'status') {
                                    final st = await showDialog<String>(
                                      context: c,
                                      builder: (_) => SimpleDialog(
                                        title: const Text('เปลี่ยนสถานะ'),
                                        children: [
                                          SimpleDialogOption(
                                            onPressed: () =>
                                                Navigator.pop(c, 'pending'),
                                            child: Text('ยังไม่เริ่ม'),
                                          ),
                                          SimpleDialogOption(
                                            onPressed: () =>
                                                Navigator.pop(c, 'in_progress'),
                                            child: Text('กำลังทำ'),
                                          ),
                                          SimpleDialogOption(
                                            onPressed: () =>
                                                Navigator.pop(c, 'completed'),
                                            child: Text('เสร็จแล้ว'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (st != null) {
                                      try {
                                        await c
                                            .read<ApiSession>()
                                            .api
                                            .updateTask(x.id, {'status': st});
                                        _refresh();
                                      } catch (e) {
                                        if (mounted)
                                          ScaffoldMessenger.of(c).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'แก้ไขสถานะไม่สำเร็จ: $e',
                                              ),
                                            ),
                                          );
                                      }
                                    }
                                  }
                                  if (v == 'delete' && await _sc(c, x.name)) {
                                    try {
                                      await c.read<ApiSession>().api.delete(
                                        '/tasks/${x.id}',
                                      );
                                      _refresh();
                                    } catch (e) {
                                      if (mounted)
                                        ScaffoldMessenger.of(c).showSnackBar(
                                          SnackBar(
                                            content: Text('ลบไม่สำเร็จ: $e'),
                                          ),
                                        );
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('แก้ไข'),
                                  ),
                                  PopupMenuItem(
                                    value: 'status',
                                    child: Text('เปลี่ยนสถานะ'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('ลบ'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      );
    },
  );
  @override
  Widget build(BuildContext context) => _buildTaskList(context);
}

class TaskDialog extends StatefulWidget {
  final FarmerTask? task;
  final List<ProductionCycle> cycles;
  const TaskDialog({this.task, required this.cycles});
  @override
  State<TaskDialog> createState() => TaskDialogState();
}

class TaskDialogState extends State<TaskDialog> {
  late TextEditingController name, desc;
  late DateTime date;
  String? cycle, status = 'pending';
  bool saving = false;
  final sts = {
    'pending': 'ยังไม่เริ่ม',
    'in_progress': 'กำลังทำ',
    'completed': 'เสร็จแล้ว',
  };
  @override
  void initState() {
    super.initState();
    final t = widget.task;
    name = TextEditingController(text: t?.name ?? '');
    desc = TextEditingController(text: t?.description ?? '');
    date = t?.dueDate ?? DateTime.now();
    cycle = widget.cycles.any((x) => x.id == t?.cycleId)
        ? t!.cycleId
        : widget.cycles.first.id;
    if (t != null && sts.containsKey(t.status)) status = t.status;
  }

  @override
  void dispose() {
    name.dispose();
    desc.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || cycle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่องานและเลือกรอบการผลิต')),
      );
      return;
    }
    setState(() => saving = true);
    final b = {
      'name': name.text.trim(),
      'cycleId': cycle,
      'dueDate': _sd(date),
      'status': status,
      'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
    };
    try {
      final a = context.read<ApiSession>().api;
      if (widget.task == null)
        await a.createTask(b);
      else
        await a.updateTask(widget.task!.id, b);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted && e is OfflineQueuedException) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(widget.task == null ? 'เพิ่มงาน' : 'แก้ไขงาน'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: cycle,
            decoration: const InputDecoration(labelText: 'เลือกรอบการผลิต'),
            items: widget.cycles
                .map(
                  (x) => DropdownMenuItem(
                    value: x.id,
                    child: Text('${x.plotName} • ${x.name}'),
                  ),
                )
                .toList(),
            onChanged: (x) => setState(() => cycle = x),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'ชื่องาน'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('วันที่กำหนด: ${_sd(date)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final x = await showDatePicker(
                context: c,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (x != null) setState(() => date = x);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: status,
            decoration: const InputDecoration(labelText: 'สถานะ'),
            items: sts.entries
                .map(
                  (x) => DropdownMenuItem(value: x.key, child: Text(x.value)),
                )
                .toList(),
            onChanged: (x) => setState(() => status = x),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: desc,
            decoration: const InputDecoration(labelText: 'คำอธิบาย (ถ้ามี)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: const Text('บันทึก'),
      ),
    ],
  );
}

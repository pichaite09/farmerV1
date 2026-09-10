import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/api_models.dart';
import '../services/api_session.dart';

const _inspectionStatuses = <String, String>{
  'good': 'ปกติ',
  'attention': 'เฝ้าระวัง',
  'critical': 'พบปัญหา',
};
const _checklistLabels = <String, String>{
  'cropHealth': 'สุขภาพพืช',
  'soilMoisture': 'ความชื้นในดิน',
  'pests': 'โรคและแมลง',
  'irrigation': 'ระบบน้ำ',
};

String _apiDate(String value) =>
    value.length >= 10 ? value.substring(0, 10) : value;

String _followUpStatusLabel(String? status) => switch (status) {
  'pending' => 'รอดำเนินการ',
  'in_progress' => 'กำลังติดตามผล',
  'completed' => 'ติดตามผลแล้ว',
  _ => 'ยังไม่มีสถานะ',
};

String _followUpSummary(FieldInspection x) {
  if (x.followUpTaskId == null) return 'ต้องติดตามผล';
  return 'งานติดตามผล: ${x.followUpTaskId} • ${_followUpStatusLabel(x.followUpStatus)}';
}

Future<bool?> showNewFieldInspectionDialog(BuildContext context) async {
  final api = context.read<ApiSession>().api;
  final results = await Future.wait([api.plots(), api.cycles()]);
  if (!context.mounted) return false;
  final plots = results[0] as List<Plot>;
  final cycles = results[1] as List<ProductionCycle>;
  if (plots.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('กรุณาสร้างแปลงเกษตรก่อน')));
    return false;
  }
  final body = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => FieldInspectionFormDialog(plots: plots, cycles: cycles),
  );
  if (body == null || !context.mounted) return false;
  final files = body.remove('_files') as List<XFile>? ?? [];
  body['inspectionDate'] = _apiDate(body['inspectionDate'] as String);
  if (body['cycleId'] == null) body.remove('cycleId');
  if (body['followUpDate'] == null) {
    body.remove('followUpDate');
  } else {
    body['followUpDate'] = _apiDate(body['followUpDate'] as String);
  }
  try {
    final inspection = await api.createFieldInspection(body);
    if (files.isNotEmpty) {
      await api.uploadAttachments(
        parentType: 'field_inspection',
        parentId: inspection.id,
        files: files,
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    return false;
  }
}

class FieldInspectionsScreen extends StatefulWidget {
  const FieldInspectionsScreen({super.key});
  @override
  State<FieldInspectionsScreen> createState() => _FieldInspectionsScreenState();
}

class _FieldInspectionsScreenState extends State<FieldInspectionsScreen> {
  late Future<List<FieldInspection>> _future;
  List<Plot> plots = [];
  List<ProductionCycle> cycles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<ApiSession>().api;
    _future = api.fieldInspections();
    Future.wait([api.plots(), api.cycles()]).then((value) {
      if (mounted)
        setState(() {
          plots = value[0] as List<Plot>;
          cycles = value[1] as List<ProductionCycle>;
        });
    });
  }

  String _plot(String id) =>
      plots.where((x) => x.id == id).firstOrNull?.name ?? 'ไม่ระบุแปลง';
  String _cycle(String? id) => id == null
      ? 'ไม่ผูกรอบผลิต'
      : cycles.where((x) => x.id == id).firstOrNull?.name ?? 'ไม่ระบุรอบ';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<List<FieldInspection>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        final items = snapshot.data ?? [];
        if (items.isEmpty)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.fact_check_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                const Text('ยังไม่มีการตรวจแปลง'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    if (await showNewFieldInspectionDialog(context) == true)
                      setState(_load);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่มการตรวจแปลง'),
                ),
              ],
            ),
          );
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final x = items[i];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.fact_check)),
                title: Text('${_plot(x.plotId)} • ${_cycle(x.cycleId)}'),
                subtitle: Text(
                  '${_inspectionStatuses[x.overallStatus] ?? x.overallStatus} • ${DateFormat('dd/MM/yyyy').format(x.inspectionDate)}${x.followUpRequired || x.followUpTaskId != null ? '\n${_followUpSummary(x)}' : ''}',
                ),
                isThreeLine: x.followUpRequired || x.followUpTaskId != null,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => FieldInspectionDetailsDialog(inspection: x),
                ),
                trailing: PopupMenuButton<String>(
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('ลบ')),
                  ],
                  onSelected: (_) async {
                    await context.read<ApiSession>().api.deleteFieldInspection(
                      x.id,
                    );
                    if (mounted) setState(_load);
                  },
                ),
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () async {
        if (await showNewFieldInspectionDialog(context) == true)
          setState(_load);
      },
      tooltip: 'เพิ่มการตรวจแปลง',
      child: const Icon(Icons.add),
    ),
  );
}

class FieldInspectionFormDialog extends StatefulWidget {
  final List<Plot> plots;
  final List<ProductionCycle> cycles;
  const FieldInspectionFormDialog({
    super.key,
    required this.plots,
    required this.cycles,
  });
  @override
  State<FieldInspectionFormDialog> createState() =>
      _FieldInspectionFormDialogState();
}

class _FieldInspectionFormDialogState extends State<FieldInspectionFormDialog> {
  final formKey = GlobalKey<FormState>();
  late String plotId, status;
  String? cycleId;
  late DateTime date;
  final notes = TextEditingController(),
      recommendation = TextEditingController();
  final checks = <String, bool>{
    for (final key in _checklistLabels.keys) key: false,
  };
  bool followUp = false;
  bool followUpDateError = false;
  DateTime? followUpDate;
  List<XFile> files = [];

  @override
  void initState() {
    super.initState();
    final firstCycle = widget.cycles.firstOrNull;
    plotId = firstCycle?.plotId ?? widget.plots.first.id;
    cycleId = firstCycle?.id;
    status = 'good';
    date = DateTime.now();
  }

  @override
  void dispose() {
    notes.dispose();
    recommendation.dispose();
    super.dispose();
  }

  Future<void> _pickDate({bool follow = false}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: followUpDate ?? date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null)
      setState(() {
        if (follow)
          followUpDate = picked;
        else
          date = picked;
        if (follow) followUpDateError = false;
      });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('เพิ่มการตรวจแปลง'),
    content: Form(
      key: formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: plotId,
              decoration: const InputDecoration(labelText: 'แปลงเกษตร'),
              items: widget.plots
                  .map(
                    (x) => DropdownMenuItem(value: x.id, child: Text(x.name)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    plotId = v;
                    cycleId = widget.cycles
                        .where((x) => x.plotId == v)
                        .firstOrNull
                        ?.id;
                  });
                }
              },
              validator: (v) => v == null ? 'กรุณาเลือกแปลง' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: cycleId,
              hint: const Text('ไม่ผูกรอบผลิต'),
              items: widget.cycles
                  .where((x) => x.plotId == plotId)
                  .map(
                    (x) => DropdownMenuItem(value: x.id, child: Text(x.name)),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() => cycleId = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: status,
              decoration: const InputDecoration(labelText: 'สถานะโดยรวม'),
              items: _inspectionStatuses.entries
                  .map(
                    (x) => DropdownMenuItem(value: x.key, child: Text(x.value)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => status = v!),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'วันที่ตรวจ: ${DateFormat('dd/MM/yyyy').format(date)}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'รายการตรวจสอบ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ..._checklistLabels.entries.map(
              (entry) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                value: checks[entry.key],
                onChanged: (v) =>
                    setState(() => checks[entry.key] = v ?? false),
              ),
            ),
            TextFormField(
              controller: notes,
              decoration: const InputDecoration(
                labelText: 'รายละเอียด / หมายเหตุ',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: recommendation,
              decoration: const InputDecoration(
                labelText: 'คำแนะนำ / การแก้ไข',
              ),
              maxLines: 2,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ต้องติดตามผล'),
              value: followUp,
              onChanged: (v) => setState(() {
                followUp = v;
                if (!v) followUpDateError = false;
              }),
            ),
            if (followUp)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  followUpDate == null
                      ? 'เลือกวันที่ติดตามผล'
                      : 'ติดตามผล: ${DateFormat('dd/MM/yyyy').format(followUpDate!)}',
                ),
                trailing: const Icon(Icons.event),
                onTap: () => _pickDate(follow: true),
              ),
            if (followUp && followUpDateError)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'กรุณาเลือกวันที่ติดตามผลก่อนบันทึก',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                files = await ImagePicker().pickMultiImage(
                  imageQuality: 70,
                  maxWidth: 1200,
                );
                setState(() {});
              },
              icon: const Icon(Icons.photo_library),
              label: Text(
                files.isEmpty
                    ? 'เลือกรูปภาพหลายรูป'
                    : 'เลือกรูปภาพแล้ว ${files.length} รูป',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          if (followUp && followUpDate == null) {
            setState(() => followUpDateError = true);
            return;
          }
          Navigator.pop(context, {
            'plotId': plotId,
            'cycleId': cycleId,
            'inspectionDate': date.toIso8601String(),
            'overallStatus': status,
            'checklist': checks,
            'notes': notes.text.trim(),
            'recommendation': recommendation.text.trim(),
            'followUpRequired': followUp,
            'followUpDate': followUpDate?.toIso8601String(),
            '_files': files,
          });
        },
        child: const Text('บันทึก'),
      ),
    ],
  );
}

class FieldInspectionDetailsDialog extends StatelessWidget {
  final FieldInspection inspection;
  const FieldInspectionDetailsDialog({super.key, required this.inspection});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('รายละเอียดการตรวจแปลง'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'สถานะ: ${_inspectionStatuses[inspection.overallStatus] ?? inspection.overallStatus}',
          ),
          const SizedBox(height: 12),
          if (inspection.notes?.isNotEmpty == true)
            Text('หมายเหตุ: ${inspection.notes}'),
          if (inspection.recommendation?.isNotEmpty == true)
            Text('คำแนะนำ: ${inspection.recommendation}'),
          if (inspection.followUpRequired ||
              inspection.followUpTaskId != null) ...[
            const SizedBox(height: 12),
            Text(_followUpSummary(inspection)),
            if (inspection.followUpDate != null)
              Text(
                'วันที่ติดตามผล: ${DateFormat('dd/MM/yyyy').format(inspection.followUpDate!)}',
              ),
          ],
          const SizedBox(height: 12),
          AttachmentGrid(parentId: inspection.id),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ปิด'),
      ),
    ],
  );
}

class AttachmentGrid extends StatefulWidget {
  final String parentId;
  const AttachmentGrid({super.key, required this.parentId});
  @override
  State<AttachmentGrid> createState() => _AttachmentGridState();
}

class _AttachmentGridState extends State<AttachmentGrid> {
  late Future<List<Attachment>> future;
  final failed = <XFile>[];
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => future = context.read<ApiSession>().api.attachments(
    'field_inspection',
    widget.parentId,
  );
  Future<void> _upload(List<XFile> files) async {
    try {
      await context.read<ApiSession>().api.uploadAttachments(
        parentType: 'field_inspection',
        parentId: widget.parentId,
        files: files,
      );
      failed.removeWhere((x) => files.contains(x));
      setState(_reload);
    } catch (_) {
      failed.addAll(files);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Attachment>>(
    future: future,
    builder: (_, snapshot) {
      final items = snapshot.data ?? [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ...items.map(
                (a) => _AttachmentTile(
                  attachment: a,
                  onDelete: () async {
                    await context.read<ApiSession>().api.deleteAttachment(a.id);
                    setState(_reload);
                  },
                ),
              ),
              ...failed.map(
                (x) => ActionChip(
                  label: Text('ลองใหม่: ${x.name}'),
                  onPressed: () => _upload([x]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final files = await ImagePicker().pickMultiImage(
                imageQuality: 70,
                maxWidth: 1200,
              );
              if (files.isNotEmpty) _upload(files);
            },
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('เพิ่มรูปภาพ'),
          ),
        ],
      );
    },
  );
}

class _AttachmentTile extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onDelete;
  const _AttachmentTile({required this.attachment, required this.onDelete});
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      FutureBuilder<Uint8List>(
        future: context.read<ApiSession>().api.attachmentContent(attachment.id),
        builder: (_, s) => SizedBox(
          width: 88,
          height: 88,
          child: s.hasData
              ? Image.memory(s.data!, fit: BoxFit.cover)
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: onDelete,
        ),
      ),
    ],
  );
}

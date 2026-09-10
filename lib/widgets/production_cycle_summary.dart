import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import 'attachment_thumbnail.dart';

String _summaryDate(DateTime date) => date.toIso8601String().split('T').first;
String _summaryMoney(double value) => value.toStringAsFixed(2);
String _summaryStatus(String value) => switch (value) {
  'active' => 'กำลังดำเนินการ',
  'completed' || 'closed' => 'เสร็จสิ้น',
  _ => value.isEmpty ? 'ไม่ระบุสถานะ' : value,
};

class ProductionCycleSummaryView extends StatelessWidget {
  final Future<List<ProductionCycleSummary>> future;
  final VoidCallback onRetry;
  const ProductionCycleSummaryView({
    super.key,
    required this.future,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<ProductionCycleSummary>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _SummaryMessage(
              icon: Icons.cloud_off,
              text: 'โหลดสรุปไม่สำเร็จ',
              action: onRetry,
            );
          }
          final cycles = snapshot.data ?? const <ProductionCycleSummary>[];
          if (cycles.isEmpty) {
            return _SummaryMessage(
              icon: Icons.summarize_outlined,
              text: 'ยังไม่มีข้อมูลสรุปรอบการผลิต',
              action: onRetry,
              actionLabel: 'ลองใหม่',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => onRetry(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
              itemCount: cycles.length,
              itemBuilder: (_, index) =>
                  _CycleSummaryCard(summary: cycles[index]),
            ),
          );
        },
      );
}

class _SummaryMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback action;
  final String actionLabel;
  const _SummaryMessage({
    required this.icon,
    required this.text,
    required this.action,
    this.actionLabel = 'ลองใหม่',
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}

class _CycleSummaryCard extends StatelessWidget {
  final ProductionCycleSummary summary;
  const _CycleSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final pending = summary.pendingTaskCount < 0 ? 0 : summary.pendingTaskCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          summary.cycleName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${summary.plotName}\n${_summaryStatus(summary.status)} • ${_summaryDate(summary.startDate)} – ${summary.endDate == null ? 'ปัจจุบัน' : _summaryDate(summary.endDate!)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountChip(label: 'กิจกรรม', value: summary.activityCount),
              _CountChip(label: 'งานทั้งหมด', value: summary.taskCount),
              _CountChip(label: 'เสร็จแล้ว', value: summary.completedTaskCount),
              _CountChip(label: 'คงค้าง', value: pending),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Amount(
                label: 'รายรับ',
                value: summary.income,
                color: Colors.green,
              ),
              _Amount(
                label: 'รายจ่าย',
                value: summary.expense,
                color: Colors.red,
              ),
              _Amount(
                label: 'กำไร/ขาดทุน',
                value: summary.profit,
                color: summary.profit >= 0 ? Colors.green : Colors.red,
              ),
            ],
          ),
          if (summary.activities.isNotEmpty) ...[
            const Divider(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'กิจกรรม',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final activity in summary.activities)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: AttachmentThumbnail(
                  parentType: 'activity',
                  parentId: activity.id,
                  size: 44,
                ),
                title: Text(activity.type),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _SummaryItemDialog(
                    title: 'กิจกรรม: ${activity.type}',
                    parentType: 'activity',
                    parentId: activity.id,
                    details: [
                      'วันที่: ${_summaryDate(activity.date)}',
                      if (activity.description?.isNotEmpty == true)
                        'รายละเอียด: ${activity.description}',
                    ],
                  ),
                ),
                subtitle: Text(
                  '${_summaryDate(activity.date)}${activity.description == null ? '' : '\n${activity.description}'}',
                ),
              ),
          ],
          if (summary.tasks.isNotEmpty) ...[
            const Divider(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('งาน', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final task in summary.tasks)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: AttachmentThumbnail(
                  parentType: 'task',
                  parentId: task.id,
                  size: 44,
                ),
                title: Text(task.name),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _SummaryItemDialog(
                    title: 'งาน: ${task.name}',
                    parentType: 'task',
                    parentId: task.id,
                    details: [
                      'กำหนด: ${_summaryDate(task.dueDate)}',
                      'สถานะ: ${task.status == 'completed' ? 'ดำเนินการแล้ว' : 'คงค้าง'}',
                      if (task.description?.isNotEmpty == true)
                        'ทำอะไรไป: ${task.description}',
                    ],
                  ),
                ),
                subtitle: Text(
                  '${task.status == 'completed' ? 'ดำเนินการแล้ว' : 'คงค้าง'} • ${_summaryDate(task.dueDate)}',
                ),
              ),
          ],
          if (summary.transactions.isNotEmpty) ...[
            const Divider(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'รายการเงิน',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final transaction in summary.transactions)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  transaction.type == 'income'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                ),
                title: Text(
                  transaction.item.isEmpty
                      ? transaction.category
                      : transaction.item,
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _SummaryItemDialog(
                    title: transaction.type == 'income' ? 'รายรับ' : 'รายจ่าย',
                    details: [
                      'รายการ: ${transaction.item.isEmpty ? transaction.category : transaction.item}',
                      'หมวดหมู่: ${transaction.category}',
                      'วันที่: ${_summaryDate(transaction.date)}',
                      'จำนวนเงิน: ${_summaryMoney(transaction.amount)} บาท',
                    ],
                  ),
                ),
                trailing: Text(_summaryMoney(transaction.amount)),
                subtitle: Text(_summaryDate(transaction.date)),
              ),
          ],
          if (summary.activities.isEmpty &&
              summary.tasks.isEmpty &&
              summary.transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('รอบนี้ยังไม่มีรายละเอียดกิจกรรม งาน หรือรายการเงิน'),
            ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int value;
  const _CountChip({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Chip(label: Text('$label: $value'));
}

class _Amount extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _Amount({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: color)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _summaryMoney(value),
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    ),
  );
}

class _SummaryItemDialog extends StatefulWidget {
  final String title;
  final String? parentType;
  final String? parentId;
  final List<String> details;

  const _SummaryItemDialog({
    required this.title,
    required this.details,
    this.parentType,
    this.parentId,
  });

  @override
  State<_SummaryItemDialog> createState() => _SummaryItemDialogState();
}

class _SummaryItemDialogState extends State<_SummaryItemDialog> {
  late Future<List<Uint8List>> _images;

  @override
  void initState() {
    super.initState();
    _images = _loadImages();
  }

  Future<List<Uint8List>> _loadImages() async {
    if (widget.parentType == null || widget.parentId == null) return [];
    final api = context.read<ApiSession>().api;
    final attachments = await api.attachments(
      widget.parentType!,
      widget.parentId!,
    );
    return Future.wait(attachments.map((x) => api.attachmentContent(x.id)));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final detail in widget.details) ...[
              Text(detail),
              const SizedBox(height: 8),
            ],
            if (widget.parentType != null) ...[
              const Divider(),
              const Text(
                'รูปภาพประกอบ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Uint8List>>(
                future: _images,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Text('โหลดรูปภาพไม่สำเร็จ');
                  }
                  final images = snapshot.data ?? const <Uint8List>[];
                  if (images.isEmpty) return const Text('ยังไม่มีรูปภาพ');
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final bytes in images)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            bytes,
                            width: 140,
                            height: 110,
                            fit: BoxFit.cover,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ปิด'),
      ),
    ],
  );
}

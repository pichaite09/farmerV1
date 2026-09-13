import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';

class NotificationBell extends StatefulWidget {
  final Color? iconColor;
  const NotificationBell({super.key, this.iconColor});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late Future<List<FarmerNotification>> _future;
  @override
  void initState() {
    super.initState();
    _future = context.read<ApiSession>().api.notifications();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FarmerNotification>>(
    future: _future,
    builder: (_, snapshot) {
      final count = snapshot.data?.where((x) => !x.isRead).length ?? 0;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'แจ้งเตือน${count > 0 ? ' $count รายการ' : ''}',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            icon: Icon(Icons.notifications_none, color: widget.iconColor),
          ),
          if (count > 0)
            Positioned(
              right: 5,
              top: 3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final Set<String> _locallyRead = <String>{};
  late Future<List<FarmerNotification>> _future;
  @override
  void initState() {
    super.initState();
    _future = context.read<ApiSession>().api.notifications();
  }

  void _reload() {
    setState(() {
      _future = context.read<ApiSession>().api.notifications();
    });
  }

  Future<void> _openDetails(FarmerNotification item) async {
    try {
      final updated = await context.read<ApiSession>().api.markNotificationRead(
        item.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(updated.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (updated.announcementType != null)
                SelectableText('รายละเอียด\n${updated.body}')
              else
                SelectableText(
                  'รายละเอียด\n${updated.body}\n\nงาน: ${updated.taskName ?? '-'}\nแปลง: ${updated.plotName ?? '-'}\nรอบการผลิต: ${updated.cycleName ?? '-'}\nกำหนดวันที่: ${updated.dueDate == null ? '-' : DateFormat('d MMMM y', 'th').format(updated.dueDate!)}',
                ),
              if (updated.announcementImageId != null) ...[
                const SizedBox(height: 12),
                FutureBuilder<Uint8List>(
                  future: context.read<ApiSession>().api.notificationImageBytes(
                    updated.id,
                  ),
                  builder: (_, image) => image.hasError
                      ? const Text('เปิดรูปภาพประกาศไม่สำเร็จ')
                      : image.hasData
                      ? Image.memory(image.data!, fit: BoxFit.contain)
                      : const Center(child: CircularProgressIndicator()),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
      if (mounted) {
        setState(() => _locallyRead.add(item.id));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เปิดรายละเอียดไม่สำเร็จ: $e')));
    }
  }

  Future<void> _clearRead() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('เคลียร์แจ้งเตือน'),
        content: const Text('ลบรายการที่อ่านแล้วออกจากรายการนี้หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('เคลียร์'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<ApiSession>().api.clearReadNotifications();
      _locallyRead.clear();
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เคลียร์รายการที่อ่านแล้วแล้ว')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เคลียร์ไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMMM y', 'th');
    return Scaffold(
      appBar: AppBar(
        title: const Text('แจ้งเตือน'),
        actions: [
          IconButton(
            tooltip: 'โหลดใหม่',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<FarmerNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Center(
              child: FilledButton(
                onPressed: _reload,
                child: const Text('โหลดใหม่'),
              ),
            );
          final items = snapshot.data ?? const <FarmerNotification>[];
          final unread = items
              .where((x) => !x.isRead && !_locallyRead.contains(x.id))
              .length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ยังไม่ได้อ่าน $unread รายการ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (items.any(
                      (x) => x.isRead || _locallyRead.contains(x.id),
                    ))
                      TextButton.icon(
                        onPressed: _clearRead,
                        icon: const Icon(Icons.clear_all),
                        label: const Text('เคลียร์ที่อ่านแล้ว'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('ยังไม่มีแจ้งเตือน'))
                    : RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final item = items[index];
                            return Card(
                              color:
                                  (item.isRead ||
                                      _locallyRead.contains(item.id))
                                  ? null
                                  : const Color(0xFFE8F5E9),
                              child: ListTile(
                                onTap: () => _openDetails(item),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF087548),
                                  child: Icon(
                                    item.isRead ||
                                            _locallyRead.contains(item.id)
                                        ? Icons.check
                                        : Icons.notifications_active,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  item.announcementType != null
                                      ? item.body
                                      : '${item.body}\nแปลง: ${item.plotName ?? '-'} • รอบการผลิต: ${item.cycleName ?? '-'}\nกำหนดวันที่ ${item.dueDate == null ? '-' : dateFormat.format(item.dueDate!)}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_session.dart';
import 'notification_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    future = context.read<ApiSession>().api.dashboard();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(child: Text('โหลดภาพรวมไม่สำเร็จ\n${snapshot.error}'));
        final d = snapshot.data!;
        final movementWorkItems =
            [
              ...List<Map<String, dynamic>>.from(
                d['recentActivities'] ?? const [],
              ),
              ...List<Map<String, dynamic>>.from(
                d['recentInspections'] ?? const [],
              ).map(
                (x) => {
                  ...x,
                  'inspection': true,
                  'type': 'ตรวจแปลง',
                  'date': x['inspectionDate'],
                },
              ),
            ]..sort(
              (a, b) => (b['date'] ?? '').toString().compareTo(
                (a['date'] ?? '').toString(),
              ),
            );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              child: _welcomeCard(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    future = context.read<ApiSession>().api.dashboard();
                  });
                  await future;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _card(
                          'แปลงเกษตร',
                          '${d['plots'] ?? 0} แปลง',
                          Icons.map,
                          const Color(0xFF168251),
                        ),
                        _card(
                          'พื้นที่รวม',
                          '${d['totalArea'] ?? 0} ไร่',
                          Icons.square_foot,
                          const Color(0xFF2D86B8),
                        ),
                        _card(
                          'กำลังดำเนินการ',
                          '${d['activeCycles'] ?? 0} รอบ',
                          Icons.sync,
                          const Color(0xFFE0A52B),
                        ),
                        _card(
                          'กำไรสุทธิ',
                          '${d['profit'] ?? 0} บาท',
                          Icons.account_balance_wallet,
                          const Color(0xFF159A78),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _financeSummary(d),
                    const SizedBox(height: 8),
                    _activityCard(
                      title: 'รายการเคลื่อนไหว ตารางงาน',
                      icon: Icons.event_note,
                      color: Colors.indigo,
                      items: List<Map<String, dynamic>>.from(
                        d['recentTasks'] ?? const [],
                      ).where((x) => x['status'] != 'completed').toList(),
                      line: (x) {
                        final status = switch (x['status']) {
                          'completed' => 'เสร็จแล้ว',
                          'in_progress' => 'กำลังทำ',
                          _ => 'ยังไม่เริ่ม',
                        };
                        final plot = (x['plotName'] ?? '').toString().trim();
                        final source = plot.isEmpty ? '' : ' • $plot';
                        return '${x['name'] ?? 'งาน'} • $status$source';
                      },
                      dateKey: 'dueDate',
                      action: _completeDashboardTask,
                    ),
                    const SizedBox(height: 8),
                    _activityCard(
                      title: 'รายการเคลื่อนไหว งาน',
                      icon: Icons.work_history,
                      color: Colors.orange,
                      items: movementWorkItems,
                      line: (x) {
                        if (x['inspection'] == true) {
                          final plot = (x['plotName'] ?? '').toString().trim();
                          final cycle = (x['cycleName'] ?? '')
                              .toString()
                              .trim();
                          final origin = [
                            if (plot.isNotEmpty) plot,
                            if (cycle.isNotEmpty) cycle,
                          ].join(' • ');
                          return 'ตรวจแปลง • ปกติ${origin.isEmpty ? '' : ' • $origin'}${(x['notes'] ?? '').toString().trim().isEmpty ? '' : ' • ${x['notes']}'}';
                        }
                        final detail = (x['description'] ?? '').toString();
                        final plot = (x['plotName'] ?? '').toString().trim();
                        final source = plot.isEmpty ? '' : ' • $plot';
                        return '${x['type'] ?? 'กิจกรรม'}${detail.isEmpty ? '' : ' • $detail'}$source';
                      },
                    ),
                    const SizedBox(height: 8),
                    _activityCard(
                      title: 'รายการเคลื่อนไหว การเงิน',
                      icon: Icons.account_balance_wallet,
                      color: Colors.teal,
                      items:
                          [
                            ...List<Map<String, dynamic>>.from(
                              d['recentTransactions'] ?? const [],
                            ),
                            ...List<Map<String, dynamic>>.from(
                              d['recentFuelRecords'] ?? const [],
                            ).map(
                              (x) => {
                                ...x,
                                'source': 'fuel',
                                'type': 'expense',
                                'category': 'น้ำมันเชื้อเพลิง',
                              },
                            ),
                          ]..sort(
                            (a, b) => (b['date'] ?? '').toString().compareTo(
                              (a['date'] ?? '').toString(),
                            ),
                          ),
                      line: (x) {
                        final amount = x['amount'] ?? 0;
                        final fuel = x['source'] == 'fuel';
                        final vehicle =
                            (x['vehicleName'] ?? x['vehicleId'] ?? '')
                                .toString();
                        final plot = (x['plotName'] ?? '').toString().trim();
                        final source = plot.isEmpty ? '' : ' • $plot';
                        final detail = fuel
                            ? 'เติมน้ำมัน ${x['fuelType'] ?? ''}${vehicle.isEmpty ? '' : ' • $vehicle'}'
                            : '${x['category'] ?? ''}';
                        return '${x['type'] == 'income' ? 'รายรับ' : 'รายจ่าย'} • $detail • $amount บาท$source';
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _financeSummary(Map<String, dynamic> d) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFDDF3E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFF176B45),
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'การเงินเดือนนี้',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'สรุปรายรับและรายจ่ายของฟาร์ม',
                      style: TextStyle(fontSize: 12, color: Color(0xFF708078)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9AA9A0)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _moneyTile(
                  'รายรับ',
                  d['income'] ?? 0,
                  Icons.arrow_downward,
                  const Color(0xFF167A4D),
                  const Color(0xFFE8F7EB),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _moneyTile(
                  'รายจ่าย',
                  d['expense'] ?? 0,
                  Icons.arrow_upward,
                  const Color(0xFFC45252),
                  const Color(0xFFFFEEEE),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _moneyTile(
    String label,
    dynamic amount,
    IconData icon,
    Color color,
    Color background,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$amount บาท',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _welcomeCard() {
    final session = context.read<ApiSession>();
    final email = session.user?.email ?? '';
    final profileName = session.user?.firstName?.trim() ?? '';
    final emailName = email.contains('@') ? email.split('@').first : email;
    final displayName = profileName.isNotEmpty
        ? profileName
        : (emailName.isEmpty ? 'เกษตรกร' : emailName);
    final date = DateFormat('วันEEEE d MMMM y', 'th').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF087548), Color(0xFF15945F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: const TextStyle(
                    color: Color(0xD9FFFFFF),
                    fontSize: 12,
                  ),
                ),
              ),
              const NotificationBell(iconColor: Colors.white),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: 'เมนูบัญชี',
                onSelected: (value) {
                  if (value == 'sync') session.syncOfflineQueue();
                  if (value == 'settings') {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  }
                  if (value == 'logout') session.logout();
                },
                itemBuilder: (_) => [
                  if (session.pendingQueueCount > 0)
                    const PopupMenuItem(
                      value: 'sync',
                      child: Text('ซิงค์รายการค้าง'),
                    ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('ตั้งค่า'),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Text('ออกจากระบบ'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'สวัสดี, คุณ$displayName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'จัดการฟาร์มของคุณได้ง่ายขึ้นในที่เดียว',
            style: TextStyle(
              color: Color(0xF2FFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Text(
            'ภาพรวมฟาร์มของคุณ',
            style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _card(
    String title,
    String value,
    IconData icon,
    Color color,
  ) => SizedBox(
    width: ((MediaQuery.sizeOf(context).width - 44) / 2).clamp(140.0, 180.0),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _completeDashboardTask(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) return;
    final result = await _completionDialog(item);
    if (result == null || !mounted) return;
    final note = result['note'] as String;
    final files = result['files'] as List<XFile>;
    try {
      final payload = <String, dynamic>{'status': 'completed'};
      if (note.trim().isNotEmpty) payload['description'] = note.trim();
      await context.read<ApiSession>().api.updateTask(id, payload);
      var uploadMessage = '';
      if (files.isNotEmpty) {
        try {
          await context.read<ApiSession>().api.uploadAttachments(
            parentType: 'task',
            parentId: id,
            files: files,
          );
          uploadMessage = ' เพิ่มรูปแล้ว ${files.length} รูป';
        } catch (e) {
          uploadMessage = ' แต่เพิ่มรูปไม่สำเร็จ';
        }
      }
      if (!mounted) return;
      setState(() => future = context.read<ApiSession>().api.dashboard());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกสำเร็จแล้ว$uploadMessage')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
      }
    }
  }

  Future<Map<String, dynamic>?> _completionDialog(
    Map<String, dynamic> item,
  ) async {
    final noteController = TextEditingController();
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
                Text(
                  '${item['name'] ?? 'งาน'}\nกรุณาระบุสิ่งที่ทำและแนบรูปประกอบได้',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
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
                'note': noteController.text,
                'files': List<XFile>.from(selected),
              }),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    return result;
  }

  Widget _activityCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) line,
    String dateKey = 'date',
    Future<void> Function(Map<String, dynamic>)? action,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text(
              'ยังไม่มีรายการเคลื่อนไหว',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...items
                .take(5)
                .map(
                  (x) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.chevron_right, color: color),
                    title: Text(line(x)),
                    subtitle: Text('${x[dateKey] ?? ''}'),
                    trailing: action != null && x['status'] != 'completed'
                        ? FilledButton.tonal(
                            onPressed: () => action(x),
                            child: const Text('สำเร็จ'),
                          )
                        : null,
                  ),
                ),
        ],
      ),
    ),
  );
}

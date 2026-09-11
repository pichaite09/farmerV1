import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/admin_models.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import '../services/farmer_api.dart';

class AdminScreen extends StatefulWidget {
  final FarmerApi? api;
  final String? currentUserId;
  const AdminScreen({super.key, this.api, this.currentUserId});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int index = 0;
  final names = const [
    'ภาพรวม',
    'ผู้ใช้งาน',
    'ข้อมูลเกษตร',
    'ประกาศ',
    'บันทึกกิจกรรม',
  ];
  final icons = const [
    Icons.dashboard,
    Icons.people,
    Icons.folder,
    Icons.campaign,
    Icons.history,
  ];
  FarmerApi get api => widget.api ?? context.read<ApiSession>().api;
  String? get currentUserId {
    if (widget.currentUserId != null || widget.api != null) {
      return widget.currentUserId;
    }
    return context.read<ApiSession>().user?.id;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      AdminDashboardPage(api: api),
      AdminUsersPage(api: api, currentUserId: currentUserId),
      AdminRecordsPage(api: api),
      AdminAnnouncementsPage(api: api),
      AdminAuditPage(api: api),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ศูนย์จัดการระบบ'),
        actions: [
          IconButton(
            tooltip: 'ออกจากระบบ',
            onPressed: () => context.read<ApiSession>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => index = i),
                  destinations: [
                    for (var i = 0; i < names.length; i++)
                      NavigationRailDestination(
                        icon: Icon(icons[i]),
                        label: Text(names[i]),
                      ),
                  ],
                ),
                Expanded(child: pages[index]),
              ],
            )
          : pages[index],
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: [
                for (var i = 0; i < names.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: names[i]),
              ],
            ),
    );
  }
}

class _Page extends StatelessWidget {
  final String title;
  final Widget child;
  const _Page({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    ),
  );
}

class _Async<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T) builder;
  const _Async({required this.future, required this.builder});
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting)
        return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Text('โหลดข้อมูลไม่สำเร็จ: ${snap.error}');
      return builder(snap.data as T);
    },
  );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(child: Text(text)),
  );
}

class _Pager extends StatelessWidget {
  final AdminPage page;
  final VoidCallback? previous, next;
  const _Pager(this.page, {this.previous, this.next});
  @override
  Widget build(BuildContext context) {
    if (page.total == 0) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '${page.offset + 1}-${page.offset + page.items.length} จาก ${page.total}',
        ),
        IconButton(onPressed: previous, icon: const Icon(Icons.chevron_left)),
        IconButton(onPressed: next, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class AdminDashboardPage extends StatelessWidget {
  final FarmerApi api;
  const AdminDashboardPage({super.key, required this.api});
  Widget _metric(MapEntry<String, int> e) => SizedBox(
    width: 220,
    child: Card(
      child: ListTile(
        leading: const Icon(Icons.analytics),
        title: Text(e.key),
        subtitle: Text('${e.value}', style: const TextStyle(fontSize: 22)),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => _Page(
    title: 'ภาพรวมระบบ',
    child: _Async(
      future: api.adminDashboard(),
      builder: (d) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: d.counts.entries.map(_metric).toList(),
      ),
    ),
  );
}

class AdminUsersPage extends StatefulWidget {
  final FarmerApi api;
  final String? currentUserId;
  const AdminUsersPage({super.key, required this.api, this.currentUserId});
  @override
  State<AdminUsersPage> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsersPage> {
  final search = TextEditingController();
  String? role, status;
  int offset = 0;
  String? mutatingUserId;
  late Future<AdminPage<ApiUser>> future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => future = widget.api.adminUsers(
    q: search.text,
    role: role,
    status: status,
    offset: offset,
  );
  void refresh() => setState(_load);
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _toggleUser(ApiUser u) async {
    if (mutatingUserId != null) return;
    setState(() => mutatingUserId = u.id);
    try {
      if (u.status == 'suspended') {
        await widget.api.adminActivateUser(u.id);
      } else {
        await widget.api.adminSuspendUser(u.id);
      }
      if (mounted) refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เปลี่ยนสถานะผู้ใช้งานไม่สำเร็จ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => mutatingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'ผู้ใช้งาน',
    child: Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            final filters = _filters(wide: wide);
            return !wide
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: filters,
                  )
                : Row(children: filters);
          },
        ),
        const SizedBox(height: 16),
        _Async(
          future: future,
          builder: (p) => Column(
            children: [
              if (p.items.isEmpty) const _Empty('ไม่พบผู้ใช้งาน'),
              ...p.items.map(_userTile),
              _Pager(
                p,
                previous: offset == 0
                    ? null
                    : () {
                        offset -= p.limit;
                        refresh();
                      },
                next: offset + p.items.length >= p.total
                    ? null
                    : () {
                        offset += p.limit;
                        refresh();
                      },
              ),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> _filters({required bool wide}) => [
    if (wide)
      Expanded(
        child: TextField(
          controller: search,
          decoration: const InputDecoration(labelText: 'ค้นหาอีเมลหรือชื่อ'),
          onSubmitted: (_) => refresh(),
        ),
      )
    else
      TextField(
        controller: search,
        decoration: const InputDecoration(labelText: 'ค้นหาอีเมลหรือชื่อ'),
        onSubmitted: (_) => refresh(),
      ),
    SizedBox(width: wide ? 10 : 0, height: wide ? 0 : 10),
    DropdownButton<String>(
      hint: const Text('บทบาท'),
      value: role,
      items: const [
        DropdownMenuItem(value: 'farmer', child: Text('เกษตรกร')),
        DropdownMenuItem(value: 'admin', child: Text('ผู้ดูแลระบบ')),
      ],
      onChanged: (v) {
        role = v;
        refresh();
      },
    ),
    DropdownButton<String>(
      hint: const Text('สถานะ'),
      value: status,
      items: const [
        DropdownMenuItem(value: 'active', child: Text('ใช้งาน')),
        DropdownMenuItem(value: 'suspended', child: Text('ระงับ')),
      ],
      onChanged: (v) {
        status = v;
        refresh();
      },
    ),
  ];

  Widget _userTile(ApiUser u) => Card(
    child: ListTile(
      title: Text(u.email),
      subtitle: Text('${u.role} · ${u.status ?? 'active'}'),
      trailing: IconButton(
        tooltip: u.id == widget.currentUserId
            ? 'ไม่สามารถระงับบัญชีที่กำลังใช้งานได้'
            : 'ระงับหรือเปิดใช้งาน',
        icon: Icon(u.status == 'suspended' ? Icons.lock_open : Icons.block),
        onPressed: u.id == widget.currentUserId || mutatingUserId != null
            ? null
            : () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(
                      u.status == 'suspended'
                          ? 'เปิดใช้งานผู้ใช้งาน?'
                          : 'ระงับผู้ใช้งาน?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('ยกเลิก'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('ยืนยัน'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await _toggleUser(u);
                }
              },
      ),
    ),
  );
}

class AdminRecordsPage extends StatefulWidget {
  final FarmerApi api;
  const AdminRecordsPage({super.key, required this.api});
  @override
  State<AdminRecordsPage> createState() => _RecordsState();
}

class _RecordsState extends State<AdminRecordsPage> {
  String type = 'activity';
  int offset = 0;
  late Future<AdminPage<Map<String, dynamic>>> future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => future = widget.api.adminRecords(type, offset: offset);
  void refresh() => setState(_load);
  @override
  Widget build(BuildContext context) => _Page(
    title: 'ข้อมูลเกษตร',
    child: Column(
      children: [
        DropdownButton<String>(
          value: type,
          items: const [
            DropdownMenuItem(value: 'activity', child: Text('กิจกรรม')),
            DropdownMenuItem(
              value: 'field_inspection',
              child: Text('ตรวจแปลง'),
            ),
            DropdownMenuItem(value: 'task', child: Text('งาน')),
            DropdownMenuItem(value: 'production_cycle', child: Text('รอบผลิต')),
            DropdownMenuItem(value: 'plot', child: Text('แปลง')),
            DropdownMenuItem(value: 'transaction', child: Text('การเงิน')),
            DropdownMenuItem(value: 'fuel_record', child: Text('เชื้อเพลิง')),
          ],
          onChanged: (v) {
            if (v != null) {
              type = v;
              offset = 0;
              refresh();
            }
          },
        ),
        _Async(
          future: future,
          builder: (p) => Column(
            children: [
              if (p.items.isEmpty) const _Empty('ไม่พบข้อมูล'),
              ...p.items.map(
                (r) => Card(
                  child: ListTile(
                    title: Text('${r['name'] ?? r['description'] ?? r['id']}'),
                    subtitle: Text('${r['createdAt'] ?? ''}'),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('รายละเอียดข้อมูล'),
                        content: Text(r.toString()),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('ปิด'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _Pager(
                p,
                previous: offset == 0
                    ? null
                    : () {
                        offset -= p.limit;
                        refresh();
                      },
                next: offset + p.items.length >= p.total
                    ? null
                    : () {
                        offset += p.limit;
                        refresh();
                      },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AdminAnnouncementsPage extends StatefulWidget {
  final FarmerApi api;
  const AdminAnnouncementsPage({super.key, required this.api});
  @override
  State<AdminAnnouncementsPage> createState() => _AnnouncementsState();
}

class _AnnouncementsState extends State<AdminAnnouncementsPage> {
  late Future<List<AdminAnnouncement>> future;
  final title = TextEditingController();
  final body = TextEditingController();
  final selectedIds = TextEditingController();
  String? sendingAnnouncementId;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => future = widget.api.adminAnnouncements();
  void refresh() => setState(_load);
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    selectedIds.dispose();
    super.dispose();
  }

  Future<void> _sendAnnouncement(AdminAnnouncement announcement) async {
    if (sendingAnnouncementId != null) return;
    setState(() => sendingAnnouncementId = announcement.id);
    try {
      await widget.api.sendAnnouncement(announcement.id);
      if (mounted) refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ส่งประกาศไม่สำเร็จ: $error')));
      }
    } finally {
      if (mounted) setState(() => sendingAnnouncementId = null);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'ประกาศ',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: compose,
          icon: const Icon(Icons.add),
          label: const Text('สร้างประกาศ'),
        ),
        const SizedBox(height: 16),
        _Async(
          future: future,
          builder: (items) => Column(
            children: [
              if (items.isEmpty) const _Empty('ยังไม่มีประกาศ'),
              ...items.map(
                (a) => Card(
                  child: ListTile(
                    title: Text(a.title),
                    subtitle: Text('${a.status} · ผู้รับ ${a.targetCount} คน'),
                    trailing: a.status == 'draft'
                        ? TextButton(
                            onPressed: sendingAnnouncementId != null
                                ? null
                                : () => _sendAnnouncement(a),
                            child: sendingAnnouncementId == a.id
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('ส่ง'),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Future<void> compose() async {
    var saving = false;
    title.clear();
    body.clear();
    selectedIds.clear();
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('สร้างประกาศ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'หัวข้อ'),
              ),
              TextField(
                controller: selectedIds,
                decoration: const InputDecoration(
                  labelText:
                      'รหัสเกษตรกรที่เลือก (คั่นด้วย ,) หรือเว้นว่างเพื่อส่งทุกคน',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: body,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'เนื้อหา'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (title.text.trim().isEmpty ||
                          body.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('กรุณากรอกหัวข้อและเนื้อหา'),
                          ),
                        );
                        return;
                      }
                      saving = true;
                      setDialogState(() {});
                      try {
                        final ids = selectedIds.text
                            .split(',')
                            .map((v) => v.trim())
                            .where((v) => v.isNotEmpty)
                            .toList();
                        final payload = <String, dynamic>{
                          'targetType': ids.isEmpty ? 'all' : 'selected',
                          if (ids.isNotEmpty) 'userIds': ids,
                          'title': title.text,
                          'body': body.text,
                        };
                        final preview = await widget.api.previewAnnouncement(
                          payload,
                        );
                        if (!context.mounted) return;
                        if ((preview['targetCount'] as num?)?.toInt() == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ไม่พบผู้รับประกาศ')),
                          );
                          return;
                        }
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('ยืนยันการสร้างประกาศ'),
                            content: Text(
                              'ผู้รับ ${preview['targetCount'] ?? 0} คน',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('กลับ'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('ยืนยัน'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await widget.api.createAnnouncement(payload);
                        if (mounted) {
                          Navigator.pop(context);
                          refresh();
                        }
                      } catch (error) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('สร้างประกาศไม่สำเร็จ: $error'),
                            ),
                          );
                        }
                      } finally {
                        saving = false;
                        if (dialogContext.mounted) setDialogState(() {});
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminAuditPage extends StatefulWidget {
  final FarmerApi api;
  const AdminAuditPage({super.key, required this.api});
  @override
  State<AdminAuditPage> createState() => _AuditState();
}

class _AuditState extends State<AdminAuditPage> {
  int offset = 0;
  late Future<AdminPage<AdminAuditLog>> future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => future = widget.api.adminAuditLogs(offset: offset);
  @override
  Widget build(BuildContext context) => _Page(
    title: 'บันทึกกิจกรรมผู้ดูแล',
    child: _Async(
      future: future,
      builder: (p) => Column(
        children: [
          if (p.items.isEmpty) const _Empty('ยังไม่มีบันทึกกิจกรรม'),
          ...p.items.map(
            (l) => Card(
              child: ListTile(
                title: Text(l.action),
                subtitle: Text(
                  '${l.targetType} · ${l.targetId}\n${l.createdAt ?? ''}',
                ),
                isThreeLine: true,
              ),
            ),
          ),
          _Pager(
            p,
            previous: offset == 0
                ? null
                : () {
                    offset -= p.limit;
                    setState(_load);
                  },
            next: offset + p.items.length >= p.total
                ? null
                : () {
                    offset += p.limit;
                    setState(_load);
                  },
          ),
        ],
      ),
    ),
  );
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/admin_models.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import '../services/farmer_api.dart';

const _ink = Color(0xff0d1110);
const _panel = Color(0xff151b18);
const _panelRaised = Color(0xff1b2420);
const _emerald = Color(0xff35d39a);
const _muted = Color(0xff9aa9a2);
const _recordTypes = {
  'activity': 'กิจกรรม',
  'field_inspection': 'ตรวจแปลง',
  'task': 'งาน',
  'production_cycle': 'รอบผลิต',
  'plot': 'แปลง',
  'transaction': 'การเงิน',
  'fuel_record': 'เชื้อเพลิง',
};

String _personName(Object? value) {
  if (value is! Map) return 'ไม่ระบุ';
  final name = [value['firstName'], value['lastName']]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(' ');
  if (name.isNotEmpty) return name;
  for (final key in ['name', 'fullName', 'email']) {
    final v = value[key];
    if (v is String && v.trim().isNotEmpty) return v;
  }
  return 'ไม่ระบุ';
}

String _thaiDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return 'ไม่ระบุวันที่';
  // Date-only values stay calendar dates; timestamps are displayed in Bangkok.
  final date = value.contains('T')
      ? parsed.toUtc().add(const Duration(hours: 7))
      : parsed;
  const months = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year + 543}';
}

class AdminScreen extends StatefulWidget {
  final FarmerApi? api;
  final String? currentUserId;
  const AdminScreen({super.key, this.api, this.currentUserId});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int index = 0;
  static const names = [
    'ภาพรวม',
    'ข้อมูลเกษตร',
    'ผู้ใช้งาน',
    'ประกาศ',
    'บันทึกกิจกรรม',
  ];
  static const icons = [
    Icons.dashboard,
    Icons.folder,
    Icons.people,
    Icons.campaign,
    Icons.history,
  ];
  FarmerApi get api => widget.api ?? context.read<ApiSession>().api;
  String? get currentUserId =>
      widget.currentUserId ??
      (widget.api == null ? context.read<ApiSession>().user?.id : null);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = [
      AdminDashboardPage(
        api: api,
        onNavigate: (i) => setState(() => index = i),
      ),
      AdminRecordsPage(api: api),
      AdminUsersPage(api: api, currentUserId: currentUserId),
      AdminAnnouncementsPage(api: api),
      AdminAuditPage(api: api),
    ];
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _ink,
        canvasColor: _panel,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _emerald,
          brightness: Brightness.dark,
        ).copyWith(surface: _panel, primary: _emerald),
        appBarTheme: const AppBarTheme(
          backgroundColor: _ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: _panel,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _panelRaised,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          labelStyle: const TextStyle(color: _muted),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'ศูนย์จัดการระบบ',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Sidebar(
                    index: index,
                    onSelect: (i) => setState(() => index = i),
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
                    NavigationDestination(
                      icon: Icon(icons[i], color: _muted),
                      selectedIcon: Icon(icons[i], color: _emerald),
                      label: names[i],
                    ),
                ],
              ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.index, required this.onSelect});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 224,
    child: Material(
      color: _panel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: _emerald),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'OPS CONSOLE',
                      style: TextStyle(
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < _AdminScreenState.names.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  selected: index == i,
                  selectedTileColor: _panelRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(
                      _AdminScreenState.icons[i],
                      size: 21,
                      color: index == i ? _emerald : _muted,
                    ),
                  ),
                  title: Text(
                    _AdminScreenState.names[i],
                    style: TextStyle(
                      color: index == i ? _emerald : Colors.white70,
                      fontWeight: index == i
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  onTap: () => onSelect(i),
                ),
              ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'ระบบผู้ดูแล • อ่านข้อมูลและจัดการการสื่อสาร',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Page extends StatelessWidget {
  final String title;
  final Widget child;
  const _Page({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ADMIN OPERATIONS',
              style: TextStyle(
                color: _emerald,
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    ),
  );
}

class _StatusStrip extends StatelessWidget {
  final String label;
  final Color color;
  final String detail;
  const _StatusStrip(this.label, this.color, this.detail);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color.withValues(alpha: .28)),
    ),
    child: Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            detail,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
      ],
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
        return const Padding(
          padding: EdgeInsets.all(36),
          child: Center(child: CircularProgressIndicator()),
        );
      if (snap.hasError)
        return const _StateBox(
          icon: Icons.cloud_off_outlined,
          title: 'โหลดข้อมูลไม่สำเร็จ',
          detail: 'ตรวจสอบการเชื่อมต่อแล้วลองใหม่อีกครั้ง',
        );
      if (!snap.hasData)
        return const _StateBox(
          icon: Icons.inbox_outlined,
          title: 'ยังไม่มีข้อมูล',
          detail: 'ไม่พบรายการสำหรับมุมมองนี้',
        );
      return builder(snap.data as T);
    },
  );
}

class _StateBox extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  const _StateBox({
    required this.icon,
    required this.title,
    required this.detail,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(34),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Icon(icon, color: _muted, size: 30),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(detail, style: const TextStyle(color: _muted)),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => _StateBox(
    icon: Icons.inbox_outlined,
    title: text,
    detail: 'ลองเปลี่ยนตัวกรองหรือกลับมาตรวจสอบภายหลัง',
  );
}

class AdminDashboardPage extends StatelessWidget {
  final FarmerApi api;
  final ValueChanged<int>? onNavigate;
  const AdminDashboardPage({super.key, required this.api, this.onNavigate});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'ภาพรวมระบบ',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StatusStrip('ข้อมูลจากระบบ', _muted, 'ไม่ใช่การวัดสุขภาพ API'),
        const SizedBox(height: 18),
        _Async(
          future: api.adminDashboard(),
          builder: (d) {
            final entries = d.counts.entries.toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ตัวชี้วัดหลัก',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: entries.isEmpty
                        ? [const _Empty('ยังไม่มีตัวชี้วัด')]
                        : entries
                              .map(
                                (e) => _Kpi(
                                  label: e.key,
                                  value: '${e.value}',
                                  width: constraints.maxWidth < 400
                                      ? (constraints.maxWidth - 12) / 2
                                      : 190,
                                ),
                              )
                              .toList(),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'การทำงานด่วน',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onNavigate == null
                          ? null
                          : () => onNavigate!(2),
                      icon: const Icon(Icons.people_outline),
                      label: const Text('ตรวจสอบผู้ใช้งาน'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onNavigate == null
                          ? null
                          : () => onNavigate!(3),
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('จัดการประกาศ'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _Kpi extends StatelessWidget {
  final String label, value;
  final double width;
  const _Kpi({required this.label, required this.value, this.width = 190});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.data_usage, color: _emerald, size: 20),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            Text(
              const {
                    'users': 'บัญชีผู้ใช้',
                    'plots': 'แปลงเกษตร',
                    'cycles': 'รอบการผลิต',
                    'activities': 'กิจกรรมเกษตร',
                    'tasks': 'งานเกษตร',
                    'notifications': 'การแจ้งเตือน',
                  }[label] ??
                  label,
              style: const TextStyle(color: _muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class AdminUsersPage extends StatefulWidget {
  final FarmerApi api;
  final String? currentUserId;
  const AdminUsersPage({super.key, required this.api, this.currentUserId});
  @override
  State<AdminUsersPage> createState() => _UsersState();
}

class _UsersState extends State<AdminUsersPage> {
  final search = TextEditingController();
  String? role, status;
  int offset = 0;
  String? mutating;
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

  Future<void> _toggle(ApiUser u) async {
    if (mutating != null) return;
    setState(() => mutating = u.id);
    try {
      if (u.status == 'suspended')
        await widget.api.adminActivateUser(u.id);
      else
        await widget.api.adminSuspendUser(u.id);
      if (mounted) refresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปลี่ยนสถานะผู้ใช้งานไม่สำเร็จ')),
        );
    } finally {
      if (mounted) setState(() => mutating = null);
    }
  }

  Future<void> _sendTestNotification(ApiUser user) async {
    if (mutating != null) return;
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _TestNotificationDialog(
        onSend: (title, body) => widget.api.adminSendTestNotification(
          userId: user.id,
          title: title,
          body: body,
        ),
      ),
    );
    if (!mounted || sent != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ส่งข้อความทดสอบสำเร็จ')));
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'ผู้ใช้งาน',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, c) {
                final fields = [
                  Expanded(
                    child: TextField(
                      controller: search,
                      onSubmitted: (_) => refresh(),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'ค้นหาอีเมลหรือชื่อ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _drop(
                    'บทบาท',
                    role,
                    const {'farmer': 'เกษตรกร', 'admin': 'ผู้ดูแลระบบ'},
                    (v) => setState(() {
                      role = v;
                      offset = 0;
                      _load();
                    }),
                  ),
                  const SizedBox(width: 10),
                  _drop(
                    'สถานะ',
                    status,
                    const {'active': 'ใช้งาน', 'suspended': 'ระงับ'},
                    (v) => setState(() {
                      status = v;
                      offset = 0;
                      _load();
                    }),
                  ),
                ];
                return c.maxWidth < 650
                    ? Column(
                        children: [
                          (fields[0] as Expanded).child,
                          const SizedBox(height: 10),
                          Wrap(spacing: 10, children: [fields[2], fields[4]]),
                        ],
                      )
                    : Row(children: fields);
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Async(
          future: future,
          builder: (p) => p.items.isEmpty
              ? const _Empty('ไม่พบผู้ใช้งาน')
              : Column(
                  children: [
                    ...p.items.map(_userCard),
                    _Pager(
                      p,
                      onPrevious: offset == 0
                          ? null
                          : () {
                              offset -= p.limit;
                              refresh();
                            },
                      onNext: offset + p.items.length >= p.total
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
  Widget _userCard(ApiUser u) {
    final suspended = u.status == 'suspended';
    final self = u.id == widget.currentUserId;
    Future<void> toggleStatus() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(suspended ? 'เปิดใช้งานผู้ใช้งาน?' : 'ระงับผู้ใช้งาน?'),
          content: Text(
            suspended
                ? 'บัญชีนี้จะกลับมาใช้งานได้'
                : 'บัญชีนี้จะไม่สามารถเข้าสู่ระบบได้',
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
      if (ok == true && mounted) _toggle(u);
    }

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: suspended || mutating != null
              ? null
              : () => _sendTestNotification(u),
          icon: const Icon(Icons.notifications_none),
          label: const Text('ส่งข้อความทดสอบ'),
        ),
        IconButton(
          tooltip: self
              ? 'ไม่สามารถระงับบัญชีที่กำลังใช้งานได้'
              : 'เปลี่ยนสถานะ',
          onPressed: self || mutating != null ? null : toggleStatus,
          icon: Icon(suspended ? Icons.lock_open : Icons.block),
        ),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final details = ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _Dot(color: suspended ? Colors.redAccent : _emerald),
            title: Text(
              _personName({
                'firstName': u.firstName,
                'lastName': u.lastName,
                'email': u.email,
              }),
            ),
            subtitle: Text(
              '${u.role == 'admin' ? 'ผู้ดูแลระบบ' : 'เกษตรกร'}  •  ${suspended ? 'ระงับ' : 'ใช้งาน'}',
              style: const TextStyle(color: _muted),
            ),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      details,
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: details),
                      actions,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _TestNotificationDialog extends StatefulWidget {
  final Future<AdminTestNotificationResult> Function(String title, String body)
  onSend;
  const _TestNotificationDialog({required this.onSend});
  @override
  State<_TestNotificationDialog> createState() =>
      _TestNotificationDialogState();
}

class _TestNotificationDialogState extends State<_TestNotificationDialog> {
  final title = TextEditingController();
  final body = TextEditingController();
  bool loading = false;
  String? error;

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final titleText = title.text.trim();
    final bodyText = body.text.trim();
    if (titleText.isEmpty || titleText.length > 200) {
      setState(() => error = 'กรุณากรอกหัวข้อไม่เกิน 200 ตัวอักษร');
      return;
    }
    if (bodyText.isEmpty || bodyText.length > 2000) {
      setState(() => error = 'กรุณากรอกข้อความไม่เกิน 2,000 ตัวอักษร');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.onSend(titleText, bodyText);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final message = e is ApiException && e.statusCode == 422
          ? 'ผู้ใช้งานนี้ยังไม่มีอุปกรณ์ที่พร้อมรับข้อความ'
          : e is ApiException && e.statusCode == 409
          ? 'ผู้ใช้งานนี้ไม่ได้อยู่ในสถานะใช้งาน'
          : 'ส่งข้อความทดสอบไม่สำเร็จ';
      if (mounted) setState(() => error = message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ส่งข้อความทดสอบ'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            enabled: !loading,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'หัวข้อ'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: body,
            enabled: !loading,
            maxLength: 2000,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'ข้อความ'),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: loading ? null : () => Navigator.pop(context, false),
        child: const Text('ยกเลิก'),
      ),
      FilledButton.icon(
        onPressed: loading ? null : _submit,
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send),
        label: Text(loading ? 'กำลังส่ง...' : 'ส่ง'),
      ),
    ],
  );
}

Widget _drop(
  String hint,
  String? value,
  Map<String, String> values,
  ValueChanged<String?> onChanged,
) => DropdownButton<String>(
  hint: Text(hint),
  value: value,
  items: values.entries
      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
      .toList(),
  onChanged: onChanged,
);

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Pager extends StatelessWidget {
  final AdminPage page;
  final VoidCallback? onPrevious, onNext;
  const _Pager(this.page, {this.onPrevious, this.onNext});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '${page.offset + 1}-${page.offset + page.items.length} จาก ${page.total}',
          style: const TextStyle(color: _muted),
        ),
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
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
  String type = 'all';
  String? farmerId;
  int offset = 0;
  late Future<AdminPage<Map<String, dynamic>>> future;
  late Future<AdminPage<ApiUser>> farmersFuture;
  @override
  void initState() {
    super.initState();
    farmersFuture = widget.api.adminUsers(role: 'farmer', limit: 100);
    _load();
  }

  void _load() =>
      future = widget.api.adminRecords(type, owner: farmerId, offset: offset);
  void refresh() => setState(_load);
  void _reloadFarmers() => setState(() {
    farmersFuture = widget.api.adminUsers(role: 'farmer', limit: 100);
  });

  String _farmerLabel(ApiUser farmer) {
    final name = [farmer.firstName, farmer.lastName]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    return name.isNotEmpty ? name : farmer.email;
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'ข้อมูลเกษตร',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            return Flex(
              direction: narrow ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: narrow ? double.infinity : 220,
                  child: _typeFilter(),
                ),
                SizedBox(
                  width: narrow ? double.infinity : 280,
                  child: _farmerFilter(),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _Async(
          future: future,
          builder: (p) => p.items.isEmpty
              ? const _Empty('ไม่พบข้อมูล')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 800)
                          return Column(
                            children: p.items.map(_record).toList(),
                          );
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            showCheckboxColumn: false,
                            columns: const [
                              DataColumn(label: Text('ประเภท')),
                              DataColumn(label: Text('รายการ')),
                              DataColumn(label: Text('ผู้บันทึก')),
                              DataColumn(label: Text('แปลง')),
                              DataColumn(label: Text('สร้างเมื่อ')),
                              DataColumn(label: Text('รูปภาพ')),
                            ],
                            rows: p.items
                                .map(
                                  (r) => DataRow(
                                    onSelectChanged: (_) => _showRecord(r),
                                    cells: [
                                      DataCell(
                                        Text(
                                          _recordTypes[r['type']] ?? 'ไม่ระบุ',
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 240,
                                          child: Text(
                                            _safeValue(r, [
                                              'name',
                                              'description',
                                              'item',
                                              'fuelType',
                                              'overallStatus',
                                            ]),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_personName(r['recorder'])),
                                      ),
                                      DataCell(
                                        Text(
                                          _formatRecordDetailValue(
                                            'plot',
                                            r['plot'],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_thaiDate('${r['createdAt']}')),
                                      ),
                                      DataCell(
                                        _RecordImagePreview(
                                          api: widget.api,
                                          attachment:
                                              _imageAttachments(r).isEmpty
                                              ? null
                                              : _imageAttachments(r).first,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
                    ),
                    _Pager(
                      p,
                      onPrevious: offset == 0
                          ? null
                          : () {
                              offset -= p.limit;
                              refresh();
                            },
                      onNext: offset + p.items.length >= p.total
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

  Widget _typeFilter() => DropdownButtonFormField<String>(
    value: type,
    decoration: const InputDecoration(labelText: 'ประเภทข้อมูล'),
    items: const [
      DropdownMenuItem(value: 'all', child: Text('ทั้งหมด')),
      DropdownMenuItem(value: 'activity', child: Text('กิจกรรม')),
      DropdownMenuItem(value: 'field_inspection', child: Text('ตรวจแปลง')),
      DropdownMenuItem(value: 'task', child: Text('งาน')),
      DropdownMenuItem(value: 'production_cycle', child: Text('รอบผลิต')),
      DropdownMenuItem(value: 'plot', child: Text('แปลง')),
      DropdownMenuItem(value: 'transaction', child: Text('การเงิน')),
      DropdownMenuItem(value: 'fuel_record', child: Text('เชื้อเพลิง')),
    ],
    onChanged: (v) {
      if (v != null)
        setState(() {
          type = v;
          offset = 0;
          _load();
        });
    },
  );

  Widget _farmerFilter() => FutureBuilder<AdminPage<ApiUser>>(
    future: farmersFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Row(
          children: [
            const Expanded(child: Text('โหลดรายชื่อเกษตรกรไม่สำเร็จ')),
            IconButton(
              tooltip: 'ลองใหม่',
              onPressed: _reloadFarmers,
              icon: const Icon(Icons.refresh),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const InputDecorator(
          decoration: InputDecoration(labelText: 'เกษตรกร'),
          child: SizedBox(
            height: 20,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        );
      }
      final farmers = snapshot.data!.items;
      final validValue =
          farmerId == null || farmers.any((f) => f.id == farmerId)
          ? farmerId
          : null;
      return DropdownButtonFormField<String?>(
        value: validValue,
        decoration: const InputDecoration(labelText: 'เกษตรกร'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('ทั้งหมด')),
          ...farmers.map(
            (farmer) => DropdownMenuItem<String?>(
              value: farmer.id,
              child: Text(_farmerLabel(farmer)),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() {
            farmerId = value;
            offset = 0;
            _load();
          });
        },
      );
    },
  );

  Widget _record(Map<String, dynamic> r) {
    final title = _safeValue(r, [
      'name',
      'title',
      'description',
      'item',
      'fuelType',
    ]);
    final date = _thaiDate(_safeValue(r, ['createdAt', 'created_at', 'date']));
    final kind = _recordTypes[r['type']] ?? 'ข้อมูลเกษตร';
    final recorder = _personName(r['recorder']);
    final images = _imageAttachments(r);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _RecordImagePreview(
          api: widget.api,
          attachment: images.isEmpty ? null : images.first,
        ),
        title: Text(title == 'ไม่ระบุ' ? kind : title),
        subtitle: Text(
          '$kind • $recorder\n$date',
          style: const TextStyle(color: _muted),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showRecord(r),
      ),
    );
  }

  void _showRecord(Map<String, dynamic> r) {
    if (r['type'] == 'production_cycle') {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 900.0),
            child: AdminProductionCycleDetailPage(
              api: widget.api,
              cycleId: '${r['id']}',
            ),
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('รายละเอียดข้อมูล'),
        content: SingleChildScrollView(
          child: _RecordDetails(api: widget.api, record: r),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}

class AdminProductionCycleDetailPage extends StatefulWidget {
  final FarmerApi api;
  final String cycleId;
  const AdminProductionCycleDetailPage({
    super.key,
    required this.api,
    required this.cycleId,
  });
  @override
  State<AdminProductionCycleDetailPage> createState() =>
      _AdminProductionCycleDetailPageState();
}

class _AdminProductionCycleDetailPageState
    extends State<AdminProductionCycleDetailPage> {
  String? filter;
  late Future<AdminProductionCycleDetail> future;
  @override
  void initState() {
    super.initState();
    future = widget.api.adminProductionCycleDetail(widget.cycleId);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: FutureBuilder<AdminProductionCycleDetail>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError)
            return const _StateBox(
              icon: Icons.cloud_off_outlined,
              title: 'โหลดรายละเอียดรอบผลิตไม่สำเร็จ',
              detail: 'ลองใหม่อีกครั้ง',
            );
          return const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final detail = snapshot.data!;
        final cycle = detail.cycle;
        final items = detail.filtered(filter);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${cycle['name'] ?? 'รอบผลิต'}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ปิด'),
                  ),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                '${cycle['cropType'] ?? ''} • ${cycle['status'] ?? ''}',
                style: const TextStyle(color: _muted),
              ),
              Text(
                'ผู้บันทึก: ${_personName(cycle['recorder'])}',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in const [
                    ('activities', 'กิจกรรม'),
                    ('fieldInspections', 'ตรวจแปลง'),
                    ('tasks', 'งาน'),
                    ('transactions', 'การเงิน'),
                    ('fuelRecords', 'เชื้อเพลิง'),
                  ])
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          '${entry.$2} ${detail.counts[entry.$1] ?? 0}',
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                value: filter,
                decoration: const InputDecoration(
                  labelText: 'กรองประเภทในไทม์ไลน์',
                ),
                items: const [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('ทั้งหมด'),
                  ),
                  DropdownMenuItem(value: 'activity', child: Text('กิจกรรม')),
                  DropdownMenuItem(
                    value: 'field_inspection',
                    child: Text('ตรวจแปลง'),
                  ),
                  DropdownMenuItem(value: 'task', child: Text('งาน')),
                  DropdownMenuItem(
                    value: 'transaction',
                    child: Text('การเงิน'),
                  ),
                  DropdownMenuItem(
                    value: 'fuel_record',
                    child: Text('เชื้อเพลิง'),
                  ),
                ],
                onChanged: (value) => setState(() => filter = value),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const _Empty('ยังไม่มีรายการในรอบผลิต')
              else
                ...items.map(
                  (item) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: item.attachments.isEmpty
                              ? const Icon(
                                  Icons.circle,
                                  size: 12,
                                  color: _emerald,
                                )
                              : InkWell(
                                  onTap: () => showDialog(
                                    context: context,
                                    builder: (_) => _AdminImageDialog(
                                      api: widget.api,
                                      attachment: _attachmentMap(
                                        item.attachments.first,
                                      ),
                                    ),
                                  ),
                                  child: _RecordImagePreview(
                                    api: widget.api,
                                    attachment: _attachmentMap(
                                      item.attachments.first,
                                    ),
                                  ),
                                ),
                          title: Text(item.title),
                          subtitle: Text(
                            '${_recordTypes[item.type] ?? 'ข้อมูล'} • ${_thaiDate(item.date)}',
                            style: const TextStyle(color: _muted),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: _RecordDetails(
                            api: widget.api,
                            record: item.data,
                            showImages: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

String _safeValue(Map<String, dynamic> r, List<String> keys) {
  for (final key in keys) {
    final value = r[key];
    if (value == null || value is Map || value is Iterable) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return 'ไม่ระบุ';
}

List<Map<String, dynamic>> _imageAttachments(Map<String, dynamic> record) {
  final raw = record['attachments'];
  if (raw is! Iterable) return const [];
  return raw
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .where((value) {
        final type = value['contentType'];
        final size = value['sizeBytes'];
        return value['id'] != null &&
            const {'image/jpeg', 'image/png', 'image/webp'}.contains(type) &&
            size is num &&
            size >= 0 &&
            size <= 10 * 1024 * 1024;
      })
      .toList();
}

Map<String, dynamic> _attachmentMap(Attachment attachment) => {
  'id': attachment.id,
  'contentType': attachment.contentType,
  'sizeBytes': attachment.sizeBytes,
};

class _RecordImagePreview extends StatefulWidget {
  final FarmerApi api;
  final Map<String, dynamic>? attachment;
  const _RecordImagePreview({required this.api, required this.attachment});
  @override
  State<_RecordImagePreview> createState() => _RecordImagePreviewState();
}

class _RecordImagePreviewState extends State<_RecordImagePreview> {
  late final Future<Uint8List> future;
  @override
  void initState() {
    super.initState();
    future = widget.attachment == null
        ? Future.value(Uint8List(0))
        : widget.api.adminAttachmentBytes('${widget.attachment!['id']}');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attachment == null) {
      return const Icon(Icons.article_outlined, color: _emerald);
    }
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) => SizedBox(
        width: 48,
        height: 48,
        child: snapshot.hasData
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              )
            : snapshot.hasError
            ? const Icon(Icons.broken_image_outlined, color: _muted)
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _AdminImageGallery extends StatelessWidget {
  final FarmerApi api;
  final List<Map<String, dynamic>> attachments;
  const _AdminImageGallery({required this.api, required this.attachments});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'รูปภาพ ${attachments.length} รายการ',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: attachments
              .map(
                (attachment) => InkWell(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) =>
                        _AdminImageDialog(api: api, attachment: attachment),
                  ),
                  child: _RecordImagePreview(api: api, attachment: attachment),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

class _AdminImageDialog extends StatelessWidget {
  final FarmerApi api;
  final Map<String, dynamic> attachment;
  const _AdminImageDialog({required this.api, required this.attachment});
  @override
  Widget build(BuildContext context) => Dialog(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<Uint8List>(
        future: api.adminAttachmentBytes('${attachment['id']}'),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const SizedBox(
              width: 280,
              height: 180,
              child: Center(child: Text('เปิดรูปภาพไม่สำเร็จ')),
            );
          }
          if (!snapshot.hasData) {
            return const SizedBox(
              width: 280,
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return InteractiveViewer(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 280,
                height: 180,
                child: Center(child: Text('รูปภาพไม่ถูกต้อง')),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _RecordDetails extends StatelessWidget {
  final FarmerApi api;
  final Map<String, dynamic> record;
  final bool showImages;
  const _RecordDetails({
    required this.api,
    required this.record,
    this.showImages = true,
  });
  @override
  Widget build(BuildContext context) {
    final allowed = [
      'name',
      'title',
      'description',
      'status',
      'type',
      'activityType',
      'inspectionDate',
      'overallStatus',
      'notes',
      'cropType',
      'dueDate',
      'amount',
      'fuelType',
      'createdAt',
      'created_at',
      'date',
      'owner',
      'recorder',
      'item',
      'area',
      'soil',
      'startDate',
      'variety',
      'category',
      'details',
      'transactionType',
      'followUpRequired',
      'plot',
      'cycle',
    ];
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 64).clamp(0.0, 420.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showImages && _imageAttachments(record).isNotEmpty)
            _AdminImageGallery(
              api: api,
              attachments: _imageAttachments(record),
            ),
          for (final key in allowed)
            if (record[key] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_label(key)}: ${_formatRecordDetailValue(key, record[key])}',
                ),
              ),
        ],
      ),
    );
  }

  String _label(String key) =>
      {
        'createdAt': 'สร้างเมื่อ',
        'created_at': 'สร้างเมื่อ',
        'description': 'รายละเอียด',
        'status': 'สถานะ',
        'name': 'ชื่อ',
        'type': 'ประเภท',
        'date': 'วันที่',
        'recorder': 'ผู้บันทึก',
        'item': 'รายการ',
        'area': 'พื้นที่',
        'soil': 'ดิน',
        'startDate': 'วันเริ่มต้น',
        'variety': 'พันธุ์',
        'category': 'หมวดหมู่',
        'details': 'รายละเอียด',
        'transactionType': 'ประเภทธุรกรรม',
        'followUpRequired': 'ต้องติดตาม',
        'owner': 'เจ้าของ',
        'plot': 'แปลง',
        'cycle': 'รอบผลิต',
        'activityType': 'ประเภทกิจกรรม',
        'inspectionDate': 'วันที่ตรวจแปลง',
        'overallStatus': 'สถานะโดยรวม',
        'notes': 'หมายเหตุ',
        'cropType': 'ชนิดพืช',
        'dueDate': 'กำหนดส่ง',
        'amount': 'จำนวนเงิน',
        'fuelType': 'ชนิดเชื้อเพลิง',
      }[key] ??
      key;
}

String _formatRecordDetailValue(String key, Object? value) {
  if (key == 'recorder' || key == 'owner') return _personName(value);
  if (key == 'type') return _recordTypes[value] ?? 'ไม่ระบุ';
  if (key.toLowerCase().contains('date') ||
      key == 'createdAt' ||
      key == 'created_at')
    return _thaiDate(value.toString());
  if (value is! Map) return value.toString();

  final nestedKeys = switch (key) {
    'owner' => const ['name', 'fullName', 'email', 'id'],
    'plot' => const ['name', 'plotName', 'id'],
    'cycle' => const ['name', 'cycleName', 'id'],
    _ => const <String>[],
  };
  for (final nestedKey in nestedKeys) {
    final nestedValue = value[nestedKey];
    if (nestedValue is String && nestedValue.trim().isNotEmpty) {
      return nestedValue;
    }
    if (nestedValue is num || nestedValue is bool) {
      return nestedValue.toString();
    }
  }
  return 'ไม่ระบุ';
}

class AdminAnnouncementsPage extends StatefulWidget {
  final FarmerApi api;
  const AdminAnnouncementsPage({super.key, required this.api});
  @override
  State<AdminAnnouncementsPage> createState() => _AnnouncementsState();
}

class _AnnouncementsState extends State<AdminAnnouncementsPage> {
  late Future<List<AdminAnnouncement>> future;
  final title = TextEditingController(),
      body = TextEditingController(),
      selectedIds = TextEditingController();
  String tab = 'all';
  String? sending;
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

  @override
  Widget build(BuildContext context) => _Page(
    title: 'ประกาศ',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final filters = SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('ทั้งหมด')),
                ButtonSegment(value: 'draft', label: Text('ฉบับร่าง')),
                ButtonSegment(value: 'sent', label: Text('ส่งแล้ว')),
              ],
              selected: {tab},
              onSelectionChanged: (v) => setState(() => tab = v.first),
            );
            final create = FilledButton.icon(
              onPressed: compose,
              icon: const Icon(Icons.add),
              label: const Text('สร้างประกาศ'),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [filters, const SizedBox(height: 12), create],
              );
            }
            return Row(
              children: [
                Expanded(child: filters),
                const SizedBox(width: 12),
                create,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _Async(
          future: future,
          builder: (items) {
            final shown = tab == 'all'
                ? items
                : items
                      .where(
                        (a) => tab == 'sent'
                            ? a.status != 'draft'
                            : a.status == tab,
                      )
                      .toList();
            return shown.isEmpty
                ? const _Empty('ยังไม่มีประกาศ')
                : Column(children: shown.map(_announcement).toList());
          },
        ),
      ],
    ),
  );
  Widget _announcement(AdminAnnouncement a) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: _Dot(color: a.status == 'draft' ? Colors.amber : _emerald),
      title: Text(a.title),
      subtitle: Text(
        '${a.status == 'draft' ? 'ฉบับร่าง' : 'ส่งแล้ว'}  •  ผู้รับ ${a.targetCount} คน',
        style: const TextStyle(color: _muted),
      ),
      trailing: a.status == 'draft'
          ? TextButton(
              onPressed: sending != null ? null : () => _send(a),
              child: sending == a.id
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('ส่ง'),
            )
          : null,
    ),
  );
  Future<void> _send(AdminAnnouncement a) async {
    setState(() => sending = a.id);
    try {
      await widget.api.sendAnnouncement(a.id);
      if (mounted) refresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ส่งประกาศไม่สำเร็จ')));
    } finally {
      if (mounted) setState(() => sending = null);
    }
  }

  Future<void> compose() async {
    title.clear();
    body.clear();
    selectedIds.clear();
    var saving = false;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('สร้างประกาศ'),
          content: SingleChildScrollView(
            child: Column(
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
                        'รหัสผู้รับ (คั่นด้วย ,) หรือเว้นว่างเพื่อส่งทุกคน',
                  ),
                ),
                TextField(
                  controller: body,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'เนื้อหา'),
                ),
              ],
            ),
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
                      setDialogState(() => saving = true);
                      try {
                        final ids = selectedIds.text
                            .split(',')
                            .map((v) => v.trim())
                            .where((v) => v.isNotEmpty)
                            .toList();
                        final payload = <String, dynamic>{
                          'targetType': ids.isEmpty ? 'all' : 'selected',
                          if (ids.isNotEmpty) 'userIds': ids,
                          'title': title.text.trim(),
                          'body': body.text.trim(),
                        };
                        final preview = await widget.api.previewAnnouncement(
                          payload,
                        );
                        if (!dialogContext.mounted) return;
                        final count =
                            (preview['targetCount'] as num?)?.toInt() ?? 0;
                        if (count == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ไม่พบผู้รับประกาศ')),
                          );
                          return;
                        }
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('ตรวจสอบตัวอย่างประกาศ'),
                            content: Text(
                              'ผู้รับ $count คน\n\n${title.text}\n${body.text}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('กลับไปแก้ไข'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('ยืนยัน'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await widget.api.createAnnouncement(payload);
                          if (mounted) {
                            Navigator.pop(context);
                            refresh();
                          }
                        }
                      } catch (_) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('สร้างประกาศไม่สำเร็จ'),
                            ),
                          );
                      } finally {
                        if (dialogContext.mounted)
                          setDialogState(() => saving = false);
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
      builder: (p) => p.items.isEmpty
          ? const _Empty('ยังไม่มีบันทึกกิจกรรม')
          : Column(
              children: [
                ...p.items.map(
                  (l) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.bolt_outlined, color: _emerald),
                      title: Text(l.action),
                      subtitle: Text(
                        '${l.targetType}  •  ${l.targetId}\n${l.createdAt ?? 'ไม่ระบุเวลา'}',
                        style: const TextStyle(color: _muted),
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
                _Pager(
                  p,
                  onPrevious: offset == 0
                      ? null
                      : () => setState(() {
                          offset -= p.limit;
                          _load();
                        }),
                  onNext: offset + p.items.length >= p.total
                      ? null
                      : () => setState(() {
                          offset += p.limit;
                          _load();
                        }),
                ),
              ],
            ),
    ),
  );
}

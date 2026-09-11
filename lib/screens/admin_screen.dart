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
    'ข้อมูลเกษตร',
    'ภาพรวม',
    'ผู้ใช้งาน',
    'ประกาศ',
    'บันทึกกิจกรรม',
  ];
  static const icons = [
    Icons.folder,
    Icons.dashboard,
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
      AdminRecordsPage(api: api),
      AdminDashboardPage(
        api: api,
        onNavigate: (i) => setState(() => index = i),
      ),
      AdminUsersPage(api: api, currentUserId: currentUserId),
      AdminAnnouncementsPage(api: api),
      AdminAuditPage(api: api),
    ];
    return Theme(
      data: Theme.of(context).copyWith(
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
  Widget build(BuildContext context) => Container(
    width: 224,
    color: _panel,
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
              Text(
                'OPS CONSOLE',
                style: TextStyle(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold,
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
                  fontWeight: index == i ? FontWeight.w700 : FontWeight.w500,
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(detail, style: const TextStyle(color: _muted, fontSize: 12)),
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
        const _StatusStrip('ระบบทำงานปกติ', _emerald, 'API พร้อมใช้งาน'),
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
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: entries.isEmpty
                      ? [const _Empty('ยังไม่มีตัวชี้วัด')]
                      : entries
                            .map((e) => _Kpi(label: e.key, value: '${e.value}'))
                            .toList(),
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
  const _Kpi({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
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
            Text(label, style: const TextStyle(color: _muted)),
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
                          fields[0],
                          const SizedBox(height: 10),
                          Row(children: fields.sublist(2)),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _Dot(color: suspended ? Colors.redAccent : _emerald),
        title: Text(u.email),
        subtitle: Text(
          '${u.role == 'admin' ? 'ผู้ดูแลระบบ' : 'เกษตรกร'}  •  ${suspended ? 'ระงับ' : 'ใช้งาน'}',
          style: const TextStyle(color: _muted),
        ),
        trailing: IconButton(
          tooltip: self
              ? 'ไม่สามารถระงับบัญชีที่กำลังใช้งานได้'
              : 'เปลี่ยนสถานะ',
          onPressed: self || mutating != null
              ? null
              : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(
                        suspended ? 'เปิดใช้งานผู้ใช้งาน?' : 'ระงับผู้ใช้งาน?',
                      ),
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
                  if (ok == true) _toggle(u);
                },
          icon: Icon(suspended ? Icons.lock_open : Icons.block),
        ),
      ),
    );
  }
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
  String type = 'activity';
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
                  children: [
                    ...p.items.map(_record),
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
    final title = _safeValue(r, ['name', 'title', 'description', 'id']);
    final date = _safeValue(r, ['createdAt', 'created_at', 'date']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.article_outlined, color: _emerald),
        title: Text(title),
        subtitle: Text(date, style: const TextStyle(color: _muted)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('รายละเอียดข้อมูล'),
            content: _RecordDetails(record: r),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ปิด'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

class _RecordDetails extends StatelessWidget {
  final Map<String, dynamic> record;
  const _RecordDetails({required this.record});
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
      'plot',
      'cycle',
    ];
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

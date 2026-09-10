import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import '../providers/category_provider.dart';

String _fd(DateTime d) => d.toIso8601String().split('T').first;
String _fm(dynamic v) =>
    (double.tryParse(v.toString()) ?? 0).toStringAsFixed(2);
Future<bool> _fc(BuildContext c, String m) => showDialog<bool>(
  context: c,
  builder: (x) => AlertDialog(
    title: const Text('ยืนยันการลบ'),
    content: Text(m),
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

Future<bool?> showNewFuelDialog(BuildContext context) async {
  final vehicles = await context.read<ApiSession>().api.vehicles();
  if (!context.mounted) return false;
  if (vehicles.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('กรุณาเพิ่มยานพาหนะก่อน')));
    return false;
  }
  return showDialog<bool>(
    context: context,
    builder: (_) => _FuelDialog(vehicles: vehicles),
  );
}

class FuelManagementScreen extends StatelessWidget {
  const FuelManagementScreen({super.key});
  @override
  Widget build(BuildContext c) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.local_gas_station), text: 'รายการ'),
            Tab(icon: Icon(Icons.directions_car), text: 'ยานพาหนะ'),
            Tab(icon: Icon(Icons.insights), text: 'สรุป'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: const [
              FuelRecordsListTab(),
              VehiclesListTab(),
              FuelSummaryTab(),
            ],
          ),
        ),
      ],
    ),
  );
}

class VehiclesListTab extends StatefulWidget {
  const VehiclesListTab({super.key});
  @override
  State<VehiclesListTab> createState() => _VehiclesState();
}

class _VehiclesState extends State<VehiclesListTab> {
  late Future<List<Vehicle>> f;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => f = context.read<ApiSession>().api.vehicles();
  void _refresh() => setState(_load);
  Future<void> _form({Vehicle? v}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _VehicleDialog(vehicle: v),
    );
    if (ok == true) _refresh();
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<Vehicle>>(
    future: f,
    builder: (c, s) {
      if (s.hasError) return Center(child: Text('โหลดไม่สำเร็จ: ${s.error}'));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final xs = s.data!;
      return Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => _form(),
          child: const Icon(Icons.add),
        ),
        body: xs.isEmpty
            ? const Center(child: Text('ยังไม่มียานพาหนะ'))
            : ListView.builder(
                itemCount: xs.length,
                itemBuilder: (_, i) {
                  final v = xs[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.agriculture),
                      title: Text(v.name),
                      subtitle: Text(
                        '${v.category}${v.licensePlate == null ? '' : ' • ${v.licensePlate}'}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (x) async {
                          if (x == 'edit') _form(v: v);
                          if (x == 'delete' && await _fc(c, 'ลบ ${v.name}?')) {
                            try {
                              await c.read<ApiSession>().api.delete(
                                '/vehicles/${v.id}',
                              );
                              _refresh();
                            } catch (e) {
                              if (mounted)
                                ScaffoldMessenger.of(c).showSnackBar(
                                  SnackBar(content: Text('ลบไม่สำเร็จ: $e')),
                                );
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                          PopupMenuItem(value: 'delete', child: Text('ลบ')),
                        ],
                      ),
                    ),
                  );
                },
              ),
      );
    },
  );
}

class _VehicleDialog extends StatefulWidget {
  final Vehicle? vehicle;
  const _VehicleDialog({this.vehicle});
  @override
  State<_VehicleDialog> createState() => _VehicleDialogState();
}

class _VehicleDialogState extends State<_VehicleDialog> {
  late TextEditingController n, p, col, d;
  String cat = 'รถยนต์';
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    n = TextEditingController(text: v?.name ?? '');
    p = TextEditingController(text: v?.licensePlate ?? '');
    col = TextEditingController(text: v?.color ?? '');
    d = TextEditingController(text: v?.details ?? '');
    if (v != null) cat = v.category;
  }

  @override
  void dispose() {
    n.dispose();
    p.dispose();
    col.dispose();
    d.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (n.text.trim().isEmpty) return;
    setState(() => saving = true);
    final b = {
      'name': n.text.trim(),
      'category': cat,
      'licensePlate': p.text.trim().isEmpty ? null : p.text.trim(),
      'color': col.text.trim().isEmpty ? null : col.text.trim(),
      'details': d.text.trim().isEmpty ? null : d.text.trim(),
    };
    try {
      final a = context.read<ApiSession>().api;
      if (widget.vehicle == null)
        await a.createVehicle(b);
      else
        await a.updateVehicle(widget.vehicle!.id, b);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(widget.vehicle == null ? 'เพิ่มยานพาหนะ' : 'แก้ไขยานพาหนะ'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          TextField(
            controller: n,
            decoration: const InputDecoration(labelText: 'ชื่อยานพาหนะ'),
          ),
          Builder(
            builder: (context) {
              final configured = context
                  .watch<CategoryProvider>()
                  .vehicleCategories;
              final values = [
                ...configured,
                if (!configured.contains(cat)) cat,
              ];
              return DropdownButtonFormField<String>(
                value: values.contains(cat) ? cat : null,
                decoration: const InputDecoration(labelText: 'หมวดหมู่'),
                items: values
                    .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                    .toList(),
                onChanged: (x) => setState(() => cat = x ?? cat),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: p,
            decoration: const InputDecoration(labelText: 'เลขทะเบียนรถ'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: col,
            decoration: const InputDecoration(labelText: 'สี'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: d,
            decoration: const InputDecoration(labelText: 'รายละเอียด'),
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

class FuelRecordsListTab extends StatefulWidget {
  const FuelRecordsListTab({super.key});
  @override
  State<FuelRecordsListTab> createState() => _FuelState();
}

class _FuelState extends State<FuelRecordsListTab> {
  late Future<List<FuelRecord>> f;
  late Future<List<Vehicle>> vf;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    f = context.read<ApiSession>().api.fuelRecords();
    vf = context.read<ApiSession>().api.vehicles();
  }

  void _refresh() => setState(_load);
  Future<void> _form(List<Vehicle> vs, {FuelRecord? r}) async {
    if (vs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเพิ่มยานพาหนะก่อน')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _FuelDialog(record: r, vehicles: vs),
    );
    if (ok == true) _refresh();
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<Vehicle>>(
    future: vf,
    builder: (c, vs) {
      if (!vs.hasData) return const Center(child: CircularProgressIndicator());
      final map = {for (final v in vs.data!) v.id: v};
      return FutureBuilder<List<FuelRecord>>(
        future: f,
        builder: (c, s) {
          if (s.hasError)
            return Center(child: Text('โหลดไม่สำเร็จ: ${s.error}'));
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          final xs = s.data!;
          return Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () => _form(vs.data!),
              child: const Icon(Icons.add),
            ),
            body: xs.isEmpty
                ? const Center(child: Text('ยังไม่มีการบันทึกการเติมน้ำมัน'))
                : ListView.builder(
                    itemCount: xs.length,
                    itemBuilder: (_, i) {
                      final r = xs[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.local_gas_station),
                          title: Text(
                            map[r.vehicleId]?.name ?? 'ไม่พบยานพาหนะ',
                          ),
                          subtitle: Text(
                            '${r.fuelType} • ${_fd(r.date)}${r.details == null ? '' : ' • ${r.details}'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${_fm(r.amount)} บาท'),
                              PopupMenuButton<String>(
                                onSelected: (x) async {
                                  if (x == 'edit') _form(vs.data!, r: r);
                                  if (x == 'delete' &&
                                      await _fc(c, 'ลบบันทึกนี้?')) {
                                    try {
                                      await c.read<ApiSession>().api.delete(
                                        '/fuel-records/${r.id}',
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
}

class _FuelDialog extends StatefulWidget {
  final FuelRecord? record;
  final List<Vehicle> vehicles;
  const _FuelDialog({this.record, required this.vehicles});
  @override
  State<_FuelDialog> createState() => _FuelDialogState();
}

class _FuelDialogState extends State<_FuelDialog> {
  late TextEditingController amount, details;
  late DateTime date;
  String? vehicle;
  String fuel = 'ดีเซล';
  bool saving = false;
  final fuels = ['เบนซิน', 'ดีเซล', 'อื่นๆ'];
  @override
  void initState() {
    super.initState();
    final r = widget.record;
    amount = TextEditingController(text: r?.amount.toString() ?? '');
    details = TextEditingController(text: r?.details ?? '');
    date = r?.date ?? DateTime.now();
    vehicle = widget.vehicles.any((v) => v.id == r?.vehicleId)
        ? r!.vehicleId
        : widget.vehicles.first.id;
    if (r != null && fuels.contains(r.fuelType)) fuel = r.fuelType;
  }

  @override
  void dispose() {
    amount.dispose();
    details.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (vehicle == null || double.tryParse(amount.text) == null) return;
    setState(() => saving = true);
    final b = {
      'vehicleId': vehicle,
      'date': _fd(date),
      'fuelType': fuel,
      'amount': double.parse(amount.text),
      'details': details.text.trim().isEmpty ? null : details.text.trim(),
    };
    try {
      final a = context.read<ApiSession>().api;
      if (widget.record == null)
        await a.createFuelRecord(b);
      else
        await a.updateFuelRecord(widget.record!.id, b);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(
      widget.record == null ? 'เพิ่มบันทึกการเติมน้ำมัน' : 'แก้ไขบันทึก',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: vehicle,
            decoration: const InputDecoration(labelText: 'เลือกยานพาหนะ'),
            items: widget.vehicles
                .map((v) => DropdownMenuItem(value: v.id, child: Text(v.name)))
                .toList(),
            onChanged: (x) => setState(() => vehicle = x),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: fuel,
            decoration: const InputDecoration(labelText: 'ชนิดน้ำมัน'),
            items: fuels
                .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                .toList(),
            onChanged: (x) => setState(() => fuel = x!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'จำนวนเงิน (บาท)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: details,
            decoration: const InputDecoration(labelText: 'รายละเอียด'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('วันที่: ${_fd(date)}'),
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

class FuelSummaryTab extends StatefulWidget {
  const FuelSummaryTab({super.key});
  @override
  State<FuelSummaryTab> createState() => _FuelSummaryState();
}

class _FuelSummaryState extends State<FuelSummaryTab> {
  String period = 'month';
  String? vehicleId;
  DateTime selectedDate = DateTime.now();
  late Future<List<Vehicle>> vehicles;
  late Future<Map<String, dynamic>> report;

  @override
  void initState() {
    super.initState();
    vehicles = context.read<ApiSession>().api.vehicles();
    _reload();
  }

  String _date(DateTime d) => d.toIso8601String().split('T').first;
  String get _periodLabel {
    if (period == 'day')
      return DateFormat('d MMMM y', 'th').format(selectedDate);
    if (period == 'year') return DateFormat('y', 'th').format(selectedDate);
    return DateFormat('MMMM y', 'th').format(selectedDate);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: period == 'day'
          ? 'เลือกวันที่'
          : period == 'year'
          ? 'เลือกปี'
          : 'เลือกเดือน',
    );
    if (picked == null || !mounted) return;
    setState(() {
      selectedDate = period == 'year'
          ? DateTime(picked.year, 1, 1)
          : period == 'month'
          ? DateTime(picked.year, picked.month, 1)
          : picked;
      _reload();
    });
  }

  ({String from, String to}) _range() {
    final now = DateTime.now();
    final from = switch (period) {
      'day' => DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      ),
      'year' => DateTime(selectedDate.year),
      _ => DateTime(selectedDate.year, selectedDate.month),
    };
    final to = period == 'day'
        ? from
        : period == 'year'
        ? DateTime(selectedDate.year, 12, 31)
        : DateTime(selectedDate.year, selectedDate.month + 1, 0);
    return (from: _date(from), to: _date(to.isAfter(now) ? now : to));
  }

  void _reload() {
    final r = _range();
    report = context.read<ApiSession>().api.fuelReport(
      from: r.from,
      to: r.to,
      vehicleId: vehicleId,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Vehicle>>(
    future: vehicles,
    builder: (context, vehicleSnapshot) {
      final vs = vehicleSnapshot.data ?? const <Vehicle>[];
      final names = {for (final v in vs) v.id: v.name};
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: period,
                    decoration: const InputDecoration(labelText: 'ช่วงเวลา'),
                    items: const [
                      DropdownMenuItem(value: 'day', child: Text('รายวัน')),
                      DropdownMenuItem(value: 'month', child: Text('รายเดือน')),
                      DropdownMenuItem(value: 'year', child: Text('รายปี')),
                    ],
                    onChanged: (v) => setState(() {
                      period = v ?? 'month';
                      _reload();
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: vehicleId,
                    decoration: const InputDecoration(labelText: 'ยานพาหนะ'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('ทุกคัน'),
                      ),
                      ...vs.map(
                        (v) => DropdownMenuItem<String?>(
                          value: v.id,
                          child: Text(v.name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      vehicleId = v;
                      _reload();
                    }),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month),
                title: Text(_periodLabel),
                subtitle: Text(
                  period == 'day'
                      ? 'วันที่'
                      : period == 'month'
                      ? 'เดือนที่เลือก'
                      : 'ปีที่เลือก',
                ),
                trailing: const Icon(Icons.edit_calendar),
                onTap: _pickDate,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: report,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Center(
                    child: Text('โหลดไม่สำเร็จ: ${snapshot.error}'),
                  );
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final data = snapshot.data!;
                final byVehicle = List<Map<String, dynamic>>.from(
                  data['byVehicle'] ?? const [],
                );
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.local_gas_station,
                          color: Colors.orange,
                        ),
                        title: Text(
                          'สรุป${period == 'day'
                              ? 'รายวัน'
                              : period == 'year'
                              ? 'รายปี'
                              : 'รายเดือน'}',
                        ),
                        subtitle: const Text('ยอดค่าเชื้อเพลิงรวม'),
                        trailing: Text(
                          '${_fm(data['totalAmount'])} บาท',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'แยกตามยานพาหนะ',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (byVehicle.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Text('ยังไม่มีข้อมูลในช่วงเวลานี้'),
                        ),
                      )
                    else
                      ...byVehicle.map(
                        (x) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.directions_car),
                            title: Text(
                              names[x['vehicleId']] ?? 'ไม่พบยานพาหนะ',
                            ),
                            trailing: Text('${_fm(x['amount'])} บาท'),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

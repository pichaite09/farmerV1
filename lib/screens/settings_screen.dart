import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import '../services/push_service.dart';

class ThaiBuddhistCalendarDelegate extends GregorianCalendarDelegate {
  const ThaiBuddhistCalendarDelegate();
  String _year(DateTime d) => '${d.year + 543}';
  @override
  String formatMonthYear(DateTime date, MaterialLocalizations localizations) =>
      '${DateFormat('MMMM', 'th').format(date)} ${_year(date)}';
  @override
  String formatMediumDate(DateTime date, MaterialLocalizations localizations) =>
      '${date.day} ${DateFormat('MMM', 'th').format(date)} ${_year(date)}';
  @override
  String formatShortMonthDay(
    DateTime date,
    MaterialLocalizations localizations,
  ) => '${date.day} ${DateFormat('MMM', 'th').format(date)}';
  @override
  String formatShortDate(DateTime date, MaterialLocalizations localizations) =>
      '${date.day}/${date.month}/${_year(date)}';
  @override
  String formatFullDate(DateTime date, MaterialLocalizations localizations) =>
      '${DateFormat('EEEE', 'th').format(date)} ${date.day} ${DateFormat('MMMM', 'th').format(date)} ${_year(date)}';
  @override
  String formatCompactDate(
    DateTime date,
    MaterialLocalizations localizations,
  ) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${_year(date)}';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  late Future<Categories> f;
  final BrowserPushService _push = createBrowserPushService();
  PushServiceStatus? _pushStatus;
  String? _pushError;
  bool _pushBusy = false;
  late final Map<String, TextEditingController> _profile;
  late final Future<void> _geoReady;
  List<Map<String, dynamic>> _provinces = [];
  String? _provinceValue, _districtValue, _subdistrictValue;

  @override
  void initState() {
    super.initState();
    final user = context.read<ApiSession>().user;
    _profile = {
      'firstName': TextEditingController(text: user?.firstName ?? ''),
      'lastName': TextEditingController(text: user?.lastName ?? ''),
      'birthDate': TextEditingController(text: user?.birthDate ?? ''),
      'houseNumber': TextEditingController(text: user?.houseNumber ?? ''),
      'phone': TextEditingController(text: user?.phone ?? ''),
    };
    if (user?.birthDate != null) {
      final date = DateTime.tryParse(user!.birthDate!);
      if (date != null) {
        _profile['birthDate']!.text =
            '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year + 543}';
      }
    }
    _provinceValue = user?.province;
    _districtValue = user?.district;
    _subdistrictValue = user?.subdistrict;
    _geoReady = _loadGeography();
    _load();
    _loadPushStatus();
  }

  Future<void> _loadGeography() async {
    final raw = await rootBundle.loadString(
      'assets/data/thailand_geography.json',
    );
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    if (mounted) setState(() => _provinces = list);
  }

  @override
  void dispose() {
    for (final controller in _profile.values) controller.dispose();
    super.dispose();
  }

  void _load() => f = context.read<ApiSession>().api.categories();

  Future<void> _loadPushStatus() async {
    try {
      final status = await _push.status();
      if (mounted) setState(() => _pushStatus = status);
    } catch (e) {
      if (mounted) setState(() => _pushError = '$e');
    }
  }

  Future<void> _setPushEnabled(bool enabled) async {
    if (_pushBusy) return;
    setState(() {
      _pushBusy = true;
      _pushError = null;
    });
    try {
      final api = context.read<ApiSession>().api;
      if (enabled) {
        _pushStatus = await _push.enable(api);
      } else {
        await _push.disable(api);
        _pushStatus = await _push.status();
      }
    } catch (e) {
      _pushError = '$e';
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  Future<void> _put(String key, List<String> values) async {
    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ต้องมีอย่างน้อยหนึ่งรายการ')),
      );
      return;
    }
    try {
      final result = await context.read<ApiSession>().api.updateCategory(
        key,
        values,
      );
      if (mounted) setState(() => f = Future.value(result));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกหมวดหมู่ไม่สำเร็จ: $e')));
    }
  }

  Future<void> _edit(String key, String title, List<String> values) async {
    final ctl = TextEditingController(text: values.join('\n'));
    final result = await showDialog<List<String>>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('แก้ไข$title'),
        content: TextField(
          controller: ctl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'หนึ่งรายการต่อหนึ่งบรรทัด',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              d,
              ctl.text
                  .split('\n')
                  .map((x) => x.trim())
                  .where((x) => x.isNotEmpty)
                  .toList(),
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (result != null) await _put(key, result);
  }

  Future<void> _add(String key, List<String> values) async {
    final ctl = TextEditingController();
    final x = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('เพิ่มรายการ'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'ชื่อรายการ'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, ctl.text.trim()),
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (x != null && x.isNotEmpty && !values.contains(x))
      await _put(key, [...values, x]);
  }

  String? _birthDateForApi() {
    final text = _profile['birthDate']!.text.trim();
    final iso = DateTime.tryParse(text);
    if (iso != null) return text.substring(0, 10);
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (m == null) return null;
    final year = int.parse(m.group(3)!) - 543;
    return '${year.toString().padLeft(4, '0')}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
  }

  Future<void> _saveProfile() async {
    try {
      final session = context.read<ApiSession>();
      final result = await session.api.updateMe({
        'firstName': _profile['firstName']!.text.trim().isEmpty
            ? null
            : _profile['firstName']!.text.trim(),
        'lastName': _profile['lastName']!.text.trim().isEmpty
            ? null
            : _profile['lastName']!.text.trim(),
        'birthDate': _birthDateForApi(),
        'houseNumber': _profile['houseNumber']!.text.trim().isEmpty
            ? null
            : _profile['houseNumber']!.text.trim(),
        'province': _provinceValue,
        'district': _districtValue,
        'subdistrict': _subdistrictValue,
        'phone': _profile['phone']!.text.trim().isEmpty
            ? null
            : _profile['phone']!.text.trim(),
      });
      session.updateUser(ApiUser.fromJson(result));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อมูลส่วนตัวแล้ว')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกข้อมูลส่วนตัวไม่สำเร็จ: $e')),
        );
      }
    }
  }

  Widget _profileCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ข้อมูลส่วนตัว',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text('อีเมล: ${context.read<ApiSession>().user?.email ?? '-'}'),
          const SizedBox(height: 12),
          TextField(
            controller: _profile['firstName'],
            decoration: const InputDecoration(labelText: 'ชื่อ'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profile['lastName'],
            decoration: const InputDecoration(labelText: 'นามสกุล'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profile['birthDate'],
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'วันเกิด',
              suffixIcon: Icon(Icons.calendar_month),
            ),
            onTap: () async {
              final text = _profile['birthDate']!.text.trim();
              final iso = DateTime.tryParse(text);
              final buddhist = RegExp(
                r'^(\d{1,2})/(\d{1,2})/(\d{4})$',
              ).firstMatch(text);
              final initial =
                  iso ??
                  (buddhist == null
                      ? DateTime(1990, 1, 1)
                      : DateTime(
                          int.parse(buddhist.group(3)!) - 543,
                          int.parse(buddhist.group(2)!),
                          int.parse(buddhist.group(1)!),
                        ));
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
                calendarDelegate: const ThaiBuddhistCalendarDelegate(),
              );
              if (picked != null) {
                _profile['birthDate']!.text =
                    '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year + 543}';
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profile['houseNumber'],
            decoration: const InputDecoration(labelText: 'บ้านเลขที่'),
          ),
          FutureBuilder<void>(
            future: _geoReady,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const LinearProgressIndicator();
              final province = _provinces
                  .where((p) => p['name'] == _provinceValue)
                  .firstOrNull;
              final districts = province == null
                  ? <Map<String, dynamic>>[]
                  : (province['districts'] as List)
                        .cast<Map<String, dynamic>>();
              final district = districts
                  .where((d) => d['name'] == _districtValue)
                  .firstOrNull;
              final subdistricts = district == null
                  ? <String>[]
                  : (district['subdistricts'] as List).cast<String>();
              return Column(
                children: [
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _provinceValue,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'จังหวัด'),
                    items: _provinces
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['name'] as String,
                            child: Text(p['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _provinceValue = v;
                      _districtValue = null;
                      _subdistrictValue = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: districts.any((d) => d['name'] == _districtValue)
                        ? _districtValue
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'อำเภอ'),
                    items: districts
                        .map(
                          (d) => DropdownMenuItem(
                            value: d['name'] as String,
                            child: Text(d['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: _provinceValue == null
                        ? null
                        : (v) => setState(() {
                            _districtValue = v;
                            _subdistrictValue = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: subdistricts.contains(_subdistrictValue)
                        ? _subdistrictValue
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'ตำบล'),
                    items: subdistricts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: _districtValue == null
                        ? null
                        : (v) => setState(() => _subdistrictValue = v),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profile['phone'],
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'เบอร์โทร'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.save),
              label: const Text('บันทึกข้อมูล'),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext c) => FutureBuilder<Categories>(
    future: f,
    builder: (c, s) {
      if (s.hasError) return Center(child: Text('โหลดไม่สำเร็จ: ${s.error}'));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final x = s.data!;
      final gs = <MapEntry<String, List<String>>>[
        MapEntry('activityCategories', x.activityCategories),
        MapEntry('plantingTypes', x.plantingTypes),
        MapEntry('soilTypes', x.soilTypes),
        MapEntry('incomeCategories', x.incomeCategories),
        MapEntry('expenseCategories', x.expenseCategories),
        MapEntry('vehicleCategories', x.vehicleCategories),
      ];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileCard(),
          const SizedBox(height: 12),
          const Text(
            'ตั้งค่าหมวดหมู่',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          ...gs.map((e) {
            final title = {
              'activityCategories': 'หมวดหมู่กิจกรรม',
              'plantingTypes': 'วิธีการปลูก',
              'soilTypes': 'ชนิดดิน',
              'incomeCategories': 'หมวดหมู่รายรับ',
              'expenseCategories': 'หมวดหมู่รายจ่าย',
              'vehicleCategories': 'หมวดหมู่ยานพาหนะ',
            }[e.key]!;
            return Card(
              child: ExpansionTile(
                leading: const Icon(Icons.category),
                title: Text(title),
                subtitle: Text(e.value.join(' • ')),
                children: [
                  ...e.value.map(
                    (v) => ListTile(
                      title: Text(v),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () =>
                            _put(e.key, e.value.where((z) => z != v).toList()),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('เพิ่มรายการ'),
                    onTap: () => _add(e.key, e.value),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('แก้ไขรายการทั้งหมด'),
                    onTap: () => _edit(e.key, title, e.value),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('การแจ้งเตือนบนเบราว์เซอร์'),
              subtitle: Text(
                !_push.supported
                    ? 'เบราว์เซอร์นี้ไม่รองรับ Web Push'
                    : _pushError ??
                          (_pushBusy
                              ? 'กำลังดำเนินการ...'
                              : (_pushStatus?.enabled == true
                                    ? 'เปิดใช้งานแล้ว'
                                    : 'ปิดอยู่ — อนุญาตเพื่อรับการแจ้งเตือน')),
              ),
              value: _pushStatus?.enabled ?? false,
              onChanged: !_push.supported || _pushBusy ? null : _setPushEnabled,
            ),
          ),
        ],
      );
    },
  );
}

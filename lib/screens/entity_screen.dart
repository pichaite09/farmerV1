import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_session.dart';

class EntityScreen extends StatefulWidget {
  final String title, path;
  final Future<List<dynamic>> Function()? loader;
  final List<String> fields;
  final bool canAdd;
  const EntityScreen({
    super.key,
    required this.title,
    required this.path,
    this.loader,
    required this.fields,
    this.canAdd = false,
  });
  @override
  State<EntityScreen> createState() => _EntityScreenState();
}

class _EntityScreenState extends State<EntityScreen> {
  late Future<List<dynamic>> future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    future =
        widget.loader?.call() ??
        context.read<ApiSession>().api.list(widget.path, (j) => j);
  }

  String val(dynamic x, String f) {
    if (x is Map) return '${x[f] ?? ''}';
    try {
      final j = (x as dynamic);
      switch (f) {
        case 'name':
          return j.name;
        case 'type':
          return j.type;
        case 'category':
          return j.category;
        case 'item':
          return j.item;
        case 'amount':
          return '${j.amount} บาท';
        case 'date':
          return '${j.date}'.split(' ').first;
        case 'status':
          return j.status;
        case 'fuelType':
          return j.fuelType;
        default:
          return '';
      }
    } catch (_) {
      return '';
    }
  }

  Future<void> _addPlot() async {
    final n = TextEditingController(),
        a = TextEditingController(),
        s = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('เพิ่มแปลงเกษตร'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: n,
              decoration: const InputDecoration(labelText: 'ชื่อแปลง'),
            ),
            TextField(
              controller: a,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'พื้นที่ (ไร่)'),
            ),
            TextField(
              controller: s,
              decoration: const InputDecoration(labelText: 'ลักษณะดิน'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (ok == true && n.text.trim().isNotEmpty) {
      try {
        await context.read<ApiSession>().api.createPlot(
          n.text.trim(),
          double.parse(a.text),
          s.text.trim().isEmpty ? null : s.text.trim(),
        );
        if (mounted) setState(_load);
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => setState(_load),
    child: FutureBuilder<List<dynamic>>(
      future: future,
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (s.hasError)
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('โหลดข้อมูลไม่สำเร็จ\n${s.error}'),
              ),
            ],
          );
        final rows = s.data ?? [];
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('ยังไม่มีข้อมูล')),
                  ),
                ...rows.map(
                  (x) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.eco),
                      title: Text(val(x, widget.fields.first)),
                      subtitle: Text(
                        widget.fields
                            .skip(1)
                            .map((f) => val(x, f))
                            .where((v) => v.isNotEmpty)
                            .join(' • '),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.canAdd)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  onPressed: _addPlot,
                  child: const Icon(Icons.add),
                ),
              ),
          ],
        );
      },
    ),
  );
}

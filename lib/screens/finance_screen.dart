import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';

String _day(DateTime d) => d.toIso8601String().split('T').first;
String _money(dynamic v) =>
    (double.tryParse(v.toString()) ?? 0).toStringAsFixed(2);
Future<bool> _confirm(BuildContext c, String m) => showDialog<bool>(
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

Future<bool?> showNewTransactionDialog(BuildContext context) async {
  final api = context.read<ApiSession>().api;
  final cycles = await api.cycles();
  final cats = await api.categories();
  if (!context.mounted) return false;
  return showDialog<bool>(
    context: context,
    builder: (_) => _TxDialog(
      cycles: cycles,
      income: cats.incomeCategories,
      expense: cats.expenseCategories,
    ),
  );
}

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});
  @override
  Widget build(BuildContext c) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.list_alt), text: 'รายการ'),
            Tab(icon: Icon(Icons.insights), text: 'สรุปผล'),
          ],
        ),
        Expanded(
          child: const TabBarView(
            children: [TransactionsScreen(), SummaryScreen()],
          ),
        ),
      ],
    ),
  );
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsState();
}

class _TransactionsState extends State<TransactionsScreen> {
  late Future<List<FarmerTransaction>> f;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => f = context.read<ApiSession>().api.transactions();
  void _refresh() => setState(_load);
  Future<void> _form({FarmerTransaction? item}) async {
    final a = context.read<ApiSession>().api;
    final cs = await a.cycles();
    final cats = await a.categories();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _TxDialog(
        transaction: item,
        cycles: cs,
        income: cats.incomeCategories,
        expense: cats.expenseCategories,
      ),
    );
    if (ok == true) _refresh();
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<FarmerTransaction>>(
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
            ? const Center(child: Text('ยังไม่มีรายการ'))
            : ListView.builder(
                itemCount: xs.length,
                itemBuilder: (_, i) {
                  final x = xs[i];
                  final inc = x.type == 'income';
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        inc ? Icons.arrow_upward : Icons.arrow_downward,
                        color: inc ? Colors.green : Colors.red,
                      ),
                      title: Text(x.item),
                      subtitle: Text('${x.category} • ${_day(x.date)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${inc ? '+' : '-'}${_money(x.amount)} บาท'),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') _form(item: x);
                              if (v == 'delete' &&
                                  await _confirm(c, 'ลบรายการ ${x.item}?')) {
                                try {
                                  await c.read<ApiSession>().api.delete(
                                    '/transactions/${x.id}',
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
                              PopupMenuItem(value: 'delete', child: Text('ลบ')),
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
}

class _TxDialog extends StatefulWidget {
  final FarmerTransaction? transaction;
  final List<ProductionCycle> cycles;
  final List<String> income, expense;
  const _TxDialog({
    this.transaction,
    required this.cycles,
    required this.income,
    required this.expense,
  });
  @override
  State<_TxDialog> createState() => _TxDialogState();
}

class _TxDialogState extends State<_TxDialog> {
  late TextEditingController item, amount;
  late String type;
  String? category, cycle;
  late DateTime date;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    type = t?.type ?? 'expense';
    item = TextEditingController(text: t?.item ?? '');
    amount = TextEditingController(text: t == null ? '' : t.amount.toString());
    date = t?.date ?? DateTime.now();
    cycle = t?.cycleId;
    final xs = type == 'income' ? widget.income : widget.expense;
    category = xs.contains(t?.category)
        ? t!.category
        : (xs.isEmpty ? null : xs.first);
  }

  @override
  void dispose() {
    item.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final n = double.tryParse(amount.text);
    if (item.text.trim().isEmpty || category == null || n == null) return;
    setState(() => saving = true);
    final b = {
      'type': type,
      'category': category,
      'item': item.text.trim(),
      'amount': n,
      'date': _day(date),
      'cycleId': cycle,
    };
    try {
      final a = context.read<ApiSession>().api;
      if (widget.transaction == null)
        await a.createTransaction(b);
      else
        await a.updateTransaction(widget.transaction!.id, b);
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
  Widget build(BuildContext c) {
    final xs = type == 'income' ? widget.income : widget.expense;
    return AlertDialog(
      title: Text(widget.transaction == null ? 'เพิ่มรายการ' : 'แก้ไขรายการ'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('รายจ่าย')),
                ButtonSegment(value: 'income', label: Text('รายรับ')),
              ],
              selected: {type},
              onSelectionChanged: (v) => setState(() {
                type = v.first;
                final cs = type == 'income' ? widget.income : widget.expense;
                category = cs.contains(category)
                    ? category
                    : (cs.isEmpty ? null : cs.first);
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: cycle ?? '',
              decoration: const InputDecoration(
                labelText: 'เกี่ยวข้องกับ (ไม่บังคับ)',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('ทั่วไป (ไม่ระบุรอบ)'),
                ),
                ...widget.cycles.map(
                  (x) => DropdownMenuItem(
                    value: x.id,
                    child: Text('${x.plotName} • ${x.name}'),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => cycle = v == '' ? null : v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: item,
              decoration: const InputDecoration(labelText: 'รายการ'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'หมวดหมู่'),
              items: xs
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => setState(() => category = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'จำนวนเงิน (บาท)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('วันที่: ${_day(date)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: c,
                  initialDate: date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => date = d);
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
}

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});
  @override
  State<SummaryScreen> createState() => _SummaryState();
}

class _SummaryState extends State<SummaryScreen> {
  String period = 'month';
  DateTime date = DateTime.now();
  late Future<Map<String, dynamic>> f;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final from = period == 'day'
        ? _day(date)
        : period == 'month'
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-01'
        : '${date.year}-01-01';
    final to = period == 'day'
        ? _day(date)
        : period == 'month'
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${DateTime(date.year, date.month + 1, 0).day}'
        : '${date.year}-12-31';
    f = context.read<ApiSession>().api.report(
      'finance',
      query: {'from': from, 'to': to},
    );
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<Map<String, dynamic>>(
    future: f,
    builder: (c, s) {
      if (s.hasError)
        return Center(child: Text('โหลดสรุปไม่สำเร็จ: ${s.error}'));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final x = s.data!;
      final cats = x['byCategory'] is List ? x['byCategory'] as List : const [];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButton<String>(
            value: period,
            items: const [
              DropdownMenuItem(value: 'day', child: Text('วัน')),
              DropdownMenuItem(value: 'month', child: Text('เดือน')),
              DropdownMenuItem(value: 'year', child: Text('ปี')),
            ],
            onChanged: (v) {
              if (v != null)
                setState(() {
                  period = v;
                  _load();
                });
            },
          ),
          TextButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: c,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null)
                setState(() {
                  date = d;
                  _load();
                });
            },
            icon: const Icon(Icons.calendar_today),
            label: Text(_day(date)),
          ),
          _metric('รายรับ', x['income'], Colors.green),
          _metric('รายจ่าย', x['expense'], Colors.red),
          _metric('กำไรสุทธิ', x['profit'], Colors.blue),
          const Text(
            'ยอดรวมตามหมวดหมู่',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...cats.map(
            (e) => ListTile(
              title: Text(e['category']?.toString() ?? ''),
              trailing: Text('${_money(e['amount'])} บาท'),
            ),
          ),
        ],
      );
    },
  );
  Widget _metric(String t, d, Color col) => Card(
    child: ListTile(
      title: Text(t),
      trailing: Text(
        '${_money(d)} บาท',
        style: TextStyle(color: col, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

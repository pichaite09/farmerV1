import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/api_session.dart';
import '../widgets/attachment_thumbnail.dart';

class PlotsScreen extends StatefulWidget {
  const PlotsScreen({super.key});
  @override
  State<PlotsScreen> createState() => _PlotsScreenState();
}

class _PlotsScreenState extends State<PlotsScreen> {
  late Future<List<Plot>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = context.read<ApiSession>().api.plots();
  void _reload() => setState(_load);

  Future<void> _form([Plot? plot]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => PlotFormDialog(plot: plot),
    );
    if (result == null || !mounted) return;
    try {
      final api = context.read<ApiSession>().api;
      if (plot == null) {
        await api.createPlot(
          result['name'] as String,
          result['area'] as double,
          result['soil'] as String?,
        );
      } else {
        await api.updatePlot(
          plot.id,
          result['name'] as String,
          result['area'] as double,
          result['soil'] as String?,
        );
      }
      _reload();
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _delete(Plot plot) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบแปลง "${plot.name}" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await context.read<ApiSession>().api.deletePlot(plot.id);
      _reload();
    } catch (e) {
      _error(e);
    }
  }

  void _error(Object e) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Plot>>(
    future: _future,
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting)
        return const Center(child: CircularProgressIndicator());
      if (snap.hasError)
        return _ErrorView(message: snap.error.toString(), onRetry: _reload);
      final plots = snap.data ?? [];
      if (plots.isEmpty)
        return _EmptyView(
          icon: Icons.landscape_outlined,
          text: 'ยังไม่มีแปลงเกษตร',
          onAdd: _form,
        );
      final total = plots.fold<double>(0, (sum, p) => sum + p.area);
      return Scaffold(
        body: Column(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Summary(
                      icon: Icons.landscape,
                      label: 'จำนวนแปลง',
                      value: '${plots.length} แปลง',
                      color: Colors.orange,
                    ),
                    _Summary(
                      icon: Icons.straighten,
                      label: 'ขนาดทั้งหมด',
                      value: '${total.toStringAsFixed(2)} ไร่',
                      color: Colors.teal,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: plots.length,
                itemBuilder: (_, i) {
                  final p = plots[i];
                  return Card(
                    child: ListTile(
                      leading: AttachmentThumbnail(parentType: 'plot', parentId: p.id),
                      title: Text(p.name),
                      subtitle: Text('ขนาด ${p.area} ไร่ • ดิน ${p.soil}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _form(p);
                          if (v == 'delete') _delete(p);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                          PopupMenuItem(value: 'delete', child: Text('ลบ')),
                        ],
                      ),
                      onTap: () => _imageAction(p),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _form(),
          tooltip: 'เพิ่มแปลงเกษตร',
          child: const Icon(Icons.add),
        ),
      );
    },
  );
  Future<void> _imageAction(Plot plot) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 800,
    );
    if (file == null || !mounted) return;
    try {
      final api = context.read<ApiSession>().api;
      final attachment = await api.uploadAttachment(
        parentType: 'plot', parentId: plot.id, file: file,
      );
      await _showImage(attachment);
      _reload();
    } catch (e) {
      _error('อัปโหลดรูปภาพไม่สำเร็จ (รูปภาพไม่ถูกเข้าคิว): $e');
    }
  }

  Future<void> _showImage(Attachment attachment) async {
    try {
      final bytes = await context.read<ApiSession>().api.attachmentContent(attachment.id);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => AlertDialog(
        content: Image.memory(bytes, fit: BoxFit.contain),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด'))],
      ));
    } catch (e) {
      _error('โหลดรูปภาพไม่สำเร็จ: $e');
    }
  }
}

class PlotFormDialog extends StatefulWidget {
  final Plot? plot;
  const PlotFormDialog({this.plot});
  @override
  State<PlotFormDialog> createState() => PlotFormDialogState();
}

class PlotFormDialogState extends State<PlotFormDialog> {
  final key = GlobalKey<FormState>();
  late final TextEditingController name, area, soil;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.plot?.name);
    area = TextEditingController(text: widget.plot?.area.toString());
    soil = TextEditingController(text: widget.plot?.soil);
  }

  @override
  void dispose() {
    name.dispose();
    area.dispose();
    soil.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.plot == null ? 'เพิ่มแปลงเกษตร' : 'แก้ไขแปลงเกษตร'),
    content: Form(
      key: key,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'ชื่อแปลง'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'กรุณากรอกชื่อแปลง' : null,
            ),
            TextFormField(
              controller: area,
              decoration: const InputDecoration(labelText: 'ขนาดพื้นที่ (ไร่)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = double.tryParse(v ?? '');
                return n == null || n <= 0 ? 'กรุณากรอกพื้นที่มากกว่า 0' : null;
              },
            ),
            TextFormField(
              controller: soil,
              decoration: const InputDecoration(labelText: 'ลักษณะดิน (ถ้ามี)'),
            ),
            const SizedBox(height: 8),
            const Text('แนบรูปภาพได้หลังบันทึกแปลง (ออนไลน์เท่านั้น)', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () {
          if (key.currentState!.validate())
            Navigator.pop(context, {
              'name': name.text.trim(),
              'area': double.parse(area.text),
              'soil': soil.text.trim().isEmpty ? null : soil.text.trim(),
            });
        },
        child: const Text('บันทึก'),
      ),
    ],
  );
}

class _Summary extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _Summary({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext c) => Column(
    children: [
      Icon(icon, color: color),
      Text(label, style: Theme.of(c).textTheme.bodySmall),
      Text(
        value,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onAdd;
  const _EmptyView({
    required this.icon,
    required this.text,
    required this.onAdd,
  });
  @override
  Widget build(BuildContext c) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 72, color: Colors.grey),
        const SizedBox(height: 12),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('เพิ่มรายการ'),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext c) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('ลองใหม่')),
      ],
    ),
  );
}

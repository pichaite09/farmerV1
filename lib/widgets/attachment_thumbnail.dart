import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_session.dart';

class AttachmentThumbnail extends StatefulWidget {
  final String parentType;
  final String parentId;
  final double size;

  const AttachmentThumbnail({
    super.key,
    required this.parentType,
    required this.parentId,
    this.size = 52,
  });

  @override
  State<AttachmentThumbnail> createState() => _AttachmentThumbnailState();
}

class _AttachmentThumbnailState extends State<AttachmentThumbnail> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List?> _load() async {
    final api = context.read<ApiSession>().api;
    final files = await api.attachments(widget.parentType, widget.parentId);
    if (files.isEmpty) return null;
    return api.attachmentContent(files.first.id);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snapshot.data!,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
            );
          }
          return _placeholder();
        },
      );

  Widget _placeholder() => SizedBox(
        width: widget.size,
        height: widget.size,
        child: const CircleAvatar(child: Icon(Icons.eco)),
      );
}

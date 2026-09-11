import 'package:flutter/material.dart';

/// Consistent loading, error, retry, and empty states for API-backed views.
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.future,
    required this.builder,
    this.empty,
    this.isEmpty,
    this.onRetry,
    this.errorLabel = 'โหลดไม่สำเร็จ',
    this.loadingLabel = 'กำลังโหลด',
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T value) builder;
  final Widget? empty;
  final bool Function(T value)? isEmpty;
  final VoidCallback? onRetry;
  final String errorLabel;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.connectionState == ConnectionState.active) {
          return Semantics(
            container: true,
            label: loadingLabel,
            liveRegion: true,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _MessageState(
            icon: Icons.cloud_off_outlined,
            label: errorLabel,
            detail: '${snapshot.error}',
            action: onRetry == null
                ? null
                : OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ลองใหม่'),
                  ),
          );
        }
        final value = snapshot.data;
        if (value == null || (isEmpty?.call(value) ?? false)) {
          return empty ??
              const _MessageState(
                icon: Icons.inbox_outlined,
                label: 'ยังไม่มีข้อมูล',
              );
        }
        return builder(context, value);
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.label,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, semanticLabel: label),
              const SizedBox(height: 12),
              Text(label, textAlign: TextAlign.center),
              if (detail != null) ...[
                const SizedBox(height: 4),
                Text(detail!, textAlign: TextAlign.center),
              ],
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/app_ui.dart';

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.loading,
    required this.child,
    this.message = '正在处理…',
  });

  final bool loading;
  final Widget child;
  final String message;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      if (loading) ...[
        const Positioned.fill(
          child: ModalBarrier(dismissible: false, color: Color(0x55F7F6F2)),
        ),
        Positioned.fill(
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: message,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2.5),
                      const SizedBox(height: AppSpacing.lg),
                      Text(message),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class LoadingButtonLabel extends StatelessWidget {
  const LoadingButtonLabel({
    super.key,
    required this.loading,
    required this.label,
  });
  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (loading) ...[
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
      Flexible(child: Text(label)),
    ],
  );
}

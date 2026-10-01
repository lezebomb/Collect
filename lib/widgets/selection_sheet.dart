import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/app_ui.dart';

/// Choice sheets share a full-width surface and leave room for short lists.
/// Longer lists grow up to the height limit, then scroll within the sheet.
Future<T?> showSelectionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double? heightFraction,
  bool scrollable = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: double.infinity),
  builder: (context) => SelectionSheet(
    title: title,
    heightFraction: heightFraction,
    scrollable: scrollable,
    child: builder(context),
  ),
);

class SelectionSheet extends StatelessWidget {
  const SelectionSheet({
    super.key,
    required this.child,
    this.title,
    this.heightFraction,
    this.scrollable = true,
  });

  final Widget child;
  final String? title;
  final double? heightFraction;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The modal's drag handle occupies another 48 logical pixels.
          final maximum = math.max(
            0.0,
            math.min(available * .86 - 48, constraints.maxHeight),
          );
          final minimum = math.min(math.max(0.0, available / 3 - 48), maximum);
          final fixed = heightFraction == null
              ? null
              : (available * heightFraction! - 48).clamp(minimum, maximum);
          final body = Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) ...[
                  Text(title!, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (scrollable) child else Expanded(child: child),
              ],
            ),
          );
          return ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: fixed ?? minimum,
              maxHeight: fixed ?? maximum,
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: scrollable
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(child: SingleChildScrollView(child: body)),
                        ],
                      )
                    : body,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Labels wrap when necessary instead of losing information to an ellipsis.
class SelectionOption extends StatelessWidget {
  const SelectionOption({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AppTheme.accent : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : AppTheme.ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

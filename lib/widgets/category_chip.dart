import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onDeleted,
    this.deleting = false,
    this.outlined = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDeleted;
  final bool deleting;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppTheme.ink;
    final height =
        36.0 + (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0, 30);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? AppTheme.accent
            : outlined
            ? const Color(0xFFF3F6F0)
            : Colors.white,
        shape: StadiumBorder(
          side: outlined
              ? BorderSide(color: AppTheme.accent.withValues(alpha: .22))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 240, minHeight: height),
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: onDeleted != null || deleting ? 4 : 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: color,
                      ),
                    ),
                  ),
                  if (onDeleted != null || deleting)
                    SizedBox(
                      width: 28,
                      height: height,
                      child: deleting
                          ? const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                            )
                          : IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: '删除$label分类',
                              onPressed: onDeleted,
                              iconSize: 16,
                              icon: Icon(Icons.close_rounded, color: color),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

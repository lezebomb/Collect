import 'package:flutter/material.dart';

/// Fits the complete label in its reserved space, including long collection names.
class AdaptiveCardText extends StatelessWidget {
  const AdaptiveCardText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scaler = MediaQuery.textScalerOf(context);
      final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: scaler,
      );
      var high = style.fontSize ?? 14;
      painter.text = TextSpan(
        text: text,
        style: effectiveStyle.copyWith(fontSize: high),
      );
      painter.layout(maxWidth: bounds.maxWidth);
      // Short names use only their natural height, leaving more cover space.
      final height = bounds.maxHeight.isFinite
          ? bounds.maxHeight
          : painter.height
                .clamp(
                  0.0,
                  36 * (scaler.scale(14) / 14).clamp(1, double.infinity),
                )
                .toDouble();
      bool fits(double size) {
        painter.text = TextSpan(
          text: text,
          style: effectiveStyle.copyWith(fontSize: size),
        );
        painter.layout(maxWidth: bounds.maxWidth);
        return painter.height <= height && painter.width <= bounds.maxWidth;
      }

      var low = 1.0;
      if (!fits(high)) {
        for (var i = 0; i < 12; i++) {
          final middle = (low + high) / 2;
          if (fits(middle)) {
            low = middle;
          } else {
            high = middle;
          }
        }
        high = low;
      }
      painter.dispose();
      return SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: effectiveStyle.copyWith(fontSize: high),
            softWrap: true,
          ),
        ),
      );
    },
  );
}

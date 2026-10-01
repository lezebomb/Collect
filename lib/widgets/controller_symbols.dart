import 'package:flutter/material.dart';

/// Four familiar controller shapes, in the same 20px slot as section icons.
class ControllerSymbols extends StatelessWidget {
  const ControllerSymbols({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 20,
    child: CustomPaint(
      painter: _SymbolsPainter(Theme.of(context).colorScheme.primary),
    ),
  );
}

class _SymbolsPainter extends CustomPainter {
  _SymbolsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20, size.height / 20);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(const Offset(5, 5), 3.1, pen);
    canvas.drawPath(
      Path()
        ..moveTo(15, 1.5)
        ..lineTo(18.5, 8)
        ..lineTo(11.5, 8)
        ..close(),
      pen,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 12, 6, 6),
        const Radius.circular(.7),
      ),
      pen,
    );
    canvas.drawLine(const Offset(12, 12), const Offset(18, 18), pen);
    canvas.drawLine(const Offset(18, 12), const Offset(12, 18), pen);
  }

  @override
  bool shouldRepaint(_SymbolsPainter oldDelegate) => oldDelegate.color != color;
}

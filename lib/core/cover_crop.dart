import 'dart:math' as math;
import 'dart:ui';

/// The editor and saved cover use one frame; cards contain it without re-cropping.
abstract final class CoverFrame {
  static const aspectRatio = 1.35;

  static Rect sourceRect(Size image, Size frame, double zoom, Offset pan) {
    final scale =
        math.max(frame.width / image.width, frame.height / image.height) *
        zoom.clamp(.05, 6.0);
    final width = frame.width / scale;
    final height = frame.height / scale;
    final center = image.center(Offset.zero) - pan / scale;
    return Rect.fromLTWH(
      width >= image.width
          ? (image.width - width) / 2
          : (center.dx - width / 2).clamp(0.0, image.width - width),
      height >= image.height
          ? (image.height - height) / 2
          : (center.dy - height / 2).clamp(0.0, image.height - height),
      width,
      height,
    );
  }
}

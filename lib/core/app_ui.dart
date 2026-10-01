import 'package:flutter/material.dart';

abstract final class AppRadius {
  static const small = 12.0;
  static const input = 16.0;
  static const card = 24.0;
  static const sheet = 28.0;
  static const pill = 999.0;
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const page = EdgeInsets.fromLTRB(20, 12, 20, 32);
}

abstract final class AppCardStyle {
  static const color = Colors.white;
  static const shadow = Color(0x0D20362F);
  static const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
  );
  static const shadows = [
    BoxShadow(color: shadow, blurRadius: 16, offset: Offset(0, 5)),
  ];
}

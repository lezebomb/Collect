import 'package:flutter/material.dart';

Future<bool?> confirmAction(
  BuildContext context, {
  required String title,
  String confirm = '确认',
  String cancel = '取消',
  String? content,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: content == null ? null : Text(content),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(confirm),
      ),
    ],
  ),
);

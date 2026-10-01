import 'package:flutter/material.dart';

typedef CatalogSelection = ({bool useImage, bool useTitle});

class CatalogSelectionDialog extends StatefulWidget {
  const CatalogSelectionDialog({super.key, required this.title});
  final String title;

  @override
  State<CatalogSelectionDialog> createState() => _CatalogSelectionDialogState();
}

class _CatalogSelectionDialogState extends State<CatalogSelectionDialog> {
  bool _useImage = true;
  bool _useTitle = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('使用这条搜索结果'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('使用该图片作为封面'),
            value: _useImage,
            onChanged: (v) => setState(() => _useImage = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('使用该结果名称'),
            value: _useTitle,
            onChanged: (v) => setState(() => _useTitle = v ?? false),
          ),
          const SizedBox(height: 8),
          Text(
            '默认保留你填写的名称。简介由你自己填写。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: !_useImage && !_useTitle
            ? null
            : () => Navigator.pop(context, (
                useImage: _useImage,
                useTitle: _useTitle,
              )),
        child: const Text('确认使用'),
      ),
    ],
  );
}

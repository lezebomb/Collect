import 'package:flutter/material.dart';

import '../core/app_ui.dart';
import 'selection_sheet.dart';

class RoundedChoiceField extends StatelessWidget {
  const RoundedChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.optionLabel,
    this.validator,
  });
  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?>? onChanged;
  final String Function(String)? optionLabel;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => FormField<String>(
    key: ValueKey(value),
    initialValue: value,
    validator: validator,
    builder: (state) => InkWell(
      borderRadius: BorderRadius.circular(AppRadius.input),
      onTap: onChanged == null
          ? null
          : () async {
              final selected = await showSelectionSheet<String>(
                context: context,
                title: label,
                builder: (context) => values.isEmpty
                    ? const Text('还没有分类，请先点击 + 添加')
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in values)
                            SelectionOption(
                              label: optionLabel?.call(option) ?? option,
                              selected: option == value,
                              onTap: () => Navigator.pop(context, option),
                            ),
                        ],
                      ),
              );
              if (selected != null) onChanged?.call(selected);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: state.errorText,
          enabled: onChanged != null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 28,
            maxWidth: 28,
            minHeight: 24,
          ),
          suffixIcon: const Icon(Icons.expand_more_rounded, size: 20),
        ),
        isEmpty: value == null,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value == null ? '' : optionLabel?.call(value!) ?? value!,
            maxLines: 1,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    ),
  );
}

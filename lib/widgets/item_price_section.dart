import 'package:flutter/material.dart';

import '../core/collection_options.dart';
import '../core/app_ui.dart';
import 'rounded_choice_field.dart';

class ItemPriceSection extends StatelessWidget {
  const ItemPriceSection({
    super.key,
    required this.purchaseDate,
    required this.price,
    required this.priceCny,
    required this.currency,
    required this.busy,
    required this.onChooseDate,
    required this.onClearDate,
    required this.onCurrency,
    required this.onEstimateCny,
  });

  final DateTime? purchaseDate;
  final TextEditingController price;
  final TextEditingController priceCny;
  final String currency;
  final bool busy;
  final VoidCallback onChooseDate;
  final VoidCallback onClearDate;
  final ValueChanged<String?> onCurrency;
  final VoidCallback onEstimateCny;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      OutlinedButton.icon(
        onPressed: busy ? null : onChooseDate,
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(purchaseDate == null ? '选择购入日期' : dateOnly(purchaseDate!)),
      ),
      if (purchaseDate != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy ? null : onClearDate,
            child: const Text('清除日期'),
          ),
        ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              enabled: !busy,
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '购入价格'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RoundedChoiceField(
              label: '货币',
              value: currency,
              values: currencies.keys.toList(),
              optionLabel: (code) => code,
              onChanged: busy ? null : onCurrency,
            ),
          ),
        ],
      ),
      if (currency != 'CNY') ...[
        const SizedBox(height: 14),
        TextFormField(
          enabled: !busy,
          controller: priceCny,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '折合人民币',
            suffixIcon: IconButton(
              tooltip: '按当前汇率估算',
              onPressed: busy ? null : onEstimateCny,
              icon: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.currency_exchange),
            ),
          ),
        ),
      ],
    ],
  );
}

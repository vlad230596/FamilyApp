import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/state/household_store.dart';

enum HouseholdAction { shopping, buy }

const urgencyLabels = {
  'urgent': 'Срочно',
  'week': 'На этой неделе',
  'background': 'Когда-нибудь',
};
Future<void> showHouseholdAction(
  BuildContext context,
  HouseholdAction action, {
  Map<String, dynamic>? item,
}) => showDialog<void>(
  context: context,
  builder: (_) => HouseholdActionDialog(action: action, item: item),
);

class HouseholdActionDialog extends ConsumerStatefulWidget {
  const HouseholdActionDialog({super.key, required this.action, this.item});
  final HouseholdAction action;
  final Map<String, dynamic>? item;
  @override
  ConsumerState<HouseholdActionDialog> createState() =>
      _HouseholdActionDialogState();
}

class _HouseholdActionDialogState extends ConsumerState<HouseholdActionDialog> {
  final _form = GlobalKey<FormState>();
  var _name = '', _category = '', _urgency = 'week', _days = '';
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = ref.read(shoppingStoreProvider.notifier);
    final id = widget.item?['id'] as int?;
    final saved = await store.run((api) async {
      switch (widget.action) {
        case HouseholdAction.shopping:
          await api.addShopping({
            'list_id': ref.read(shoppingStoreProvider).data['list_id'],
            'name': _name,
            'category': _category,
            'urgency': _urgency,
          });
        case HouseholdAction.buy:
          await api.buyShopping(
            id!,
            _days.trim().isEmpty ? null : int.parse(_days),
          );
      }
    }, mutation: true);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error =
            ref.read(shoppingStoreProvider).error ?? 'Не удалось сохранить.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.action) {
      HouseholdAction.shopping => 'Добавить покупку',
      HouseholdAction.buy => 'Куплено: ${widget.item?['name']}',
    };
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.action == HouseholdAction.shopping) ...[
                    TextFormField(
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Что купить',
                      ),
                      maxLength: 200,
                      onChanged: (v) => _name = v.trim(),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Введите название'
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _urgency,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Срочность'),
                      items: [
                        for (final entry in urgencyLabels.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: _busy ? null : (v) => _urgency = v!,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_busy,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Категория (необязательно)',
                      ),
                      onChanged: (v) => _category = v.trim(),
                    ),
                    const Text(
                      'Повторное добавление повышает срочность, не создавая дубль.',
                    ),
                  ],
                  if (widget.action == HouseholdAction.buy) ...[
                    const Text(
                      'Вернуть в список через несколько дней? Оставьте поле пустым для разовой покупки.',
                    ),
                    TextFormField(
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Вернуть через, дней',
                      ),
                      onChanged: (v) => _days = v,
                      validator: (v) =>
                          v == null ||
                              v.trim().isEmpty ||
                              (int.tryParse(v) != null &&
                                  int.parse(v) >= 1 &&
                                  int.parse(v) <= 3650)
                          ? null
                          : 'От 1 до 3650 дней',
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Сохранение…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

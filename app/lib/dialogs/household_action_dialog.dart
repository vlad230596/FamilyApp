import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/state/household_store.dart';
import 'package:familyapp/utils/dates.dart';

enum HouseholdAction { shopping, buy, complete, review, away }

const urgencyLabels = {
  'urgent': 'Срочно',
  'week': 'На этой неделе',
  'background': 'Когда-нибудь',
};
const ratingLabels = {
  'bad': 'Плохо',
  'normal': 'Нормально',
  'great': 'Отлично',
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
  var _name = '',
      _category = '',
      _urgency = 'week',
      _rating = 'normal',
      _days = '';
  late int? _performer =
      widget.item?['assigned_member_id'] as int? ??
      ref.read(authStoreProvider).member?.id;
  bool _approved = true, _busy = false;
  var _start = DateTime.now(), _end = DateTime.now();
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final shopping =
        widget.action == HouseholdAction.shopping ||
        widget.action == HouseholdAction.buy;
    final store = shopping
        ? ref.read(shoppingStoreProvider.notifier)
        : ref.read(dutiesStoreProvider.notifier);
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
        case HouseholdAction.complete:
          await api.completeDuty(id!, {
            'performer_member_id': _performer,
            'rating': _rating,
          });
        case HouseholdAction.review:
          await api.reviewDuty(id!, _approved, _rating);
        case HouseholdAction.away:
          await api.saveAway(dateToIso(_start), dateToIso(_end));
      }
    }, mutation: true);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error =
            (shopping
                    ? ref.read(shoppingStoreProvider)
                    : ref.read(dutiesStoreProvider))
                .error ??
            'Не удалось сохранить.';
      });
    }
  }

  Widget _ratingField() => DropdownButtonFormField<String>(
    initialValue: _rating,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Оценка'),
    items: [
      for (final entry in ratingLabels.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: _busy ? null : (v) => _rating = v!,
  );

  Future<void> _pickDate(bool start) async {
    final value = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          _start = value;
          if (_end.isBefore(value)) _end = value;
        } else {
          _end = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = ref.watch(authStoreProvider).isParent;
    final members = ref.watch(familyStoreProvider).members;
    final title = switch (widget.action) {
      HouseholdAction.shopping => 'Добавить покупку',
      HouseholdAction.buy => 'Куплено: ${widget.item?['name']}',
      HouseholdAction.complete => 'Отметить выполнение',
      HouseholdAction.review => 'Подтвердить выполнение',
      HouseholdAction.away => 'Отсутствие семьи',
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
                  if (widget.action == HouseholdAction.complete && parent) ...[
                    DropdownButtonFormField<int>(
                      key: ValueKey('performer-${members.length}'),
                      initialValue: members.any((m) => m.id == _performer)
                          ? _performer
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Кто выполнил',
                      ),
                      items: [
                        for (final m in members)
                          DropdownMenuItem(value: m.id, child: Text(m.name)),
                      ],
                      onChanged: _busy ? null : (v) => _performer = v,
                      validator: (v) =>
                          v == null ? 'Выберите исполнителя' : null,
                    ),
                    const SizedBox(height: 16),
                    _ratingField(),
                  ],
                  if (widget.action == HouseholdAction.complete && !parent)
                    const Text(
                      'Отметка будет отправлена родителю для подтверждения.',
                    ),
                  if (widget.action == HouseholdAction.review) ...[
                    Text(
                      'Исполнитель: ${widget.item?['performer_name'] ?? '—'}',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Подтвердить'),
                      subtitle: const Text(
                        'Выключите, чтобы вернуть на доработку',
                      ),
                      value: _approved,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _approved = v),
                    ),
                    if (_approved) _ratingField(),
                  ],
                  if (widget.action == HouseholdAction.away) ...[
                    const Text(
                      'Оба дня включены. Дежурства в этот период не создают долг и не дают компенсацию.',
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _pickDate(true),
                      child: Text('С ${formatDate(_start)}'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _pickDate(false),
                      child: Text('По ${formatDate(_end)}'),
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
            onPressed:
                _busy ||
                    (parent &&
                        widget.action == HouseholdAction.complete &&
                        members.isEmpty)
                ? null
                : _save,
            child: Text(_busy ? 'Сохранение…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/models/chore.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/state/household_store.dart';
import 'package:familyapp/utils/dates.dart';

Future<void> showDutyDialog(
  BuildContext context, {
  Map<String, dynamic>? duty,
}) => showDialog<void>(
  context: context,
  builder: (_) => DutyDialog(duty: duty),
);

class DutyDialog extends ConsumerStatefulWidget {
  const DutyDialog({super.key, this.duty});
  final Map<String, dynamic>? duty;
  @override
  ConsumerState<DutyDialog> createState() => _DutyDialogState();
}

class _DutyDialogState extends ConsumerState<DutyDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.duty?['title'] as String?,
  );
  late final _zone = TextEditingController(
    text: widget.duty?['timezone'] as String? ?? 'Europe/Moscow',
  );
  late final _weekdays = Set<int>.from(
    widget.duty?['weekdays'] as List? ?? [1, 2, 3, 4, 5, 6, 7],
  );
  late final _assignments = Map<String, dynamic>.from(
    widget.duty?['assignments'] as Map? ?? {},
  );
  late var _start = DateTime.parse(
    widget.duty?['start_date'] as String? ?? dateToIso(DateTime.now()),
  );
  late var _clock = TimeOfDay(
    hour: int.parse(
      (widget.duty?['reminder_time'] as String? ?? '18:00').split(':')[0],
    ),
    minute: int.parse(
      (widget.duty?['reminder_time'] as String? ?? '18:00').split(':')[1],
    ),
  );
  late var _active = widget.duty?['active'] as bool? ?? true;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _zone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_weekdays.isEmpty) {
      setState(() => _error = 'Выберите хотя бы один день.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = ref.read(dutiesStoreProvider.notifier);
    final data = <String, dynamic>{
      'title': _title.text.trim(),
      'timezone': _zone.text.trim(),
      'start_date': dateToIso(_start),
      'weekdays': _weekdays.toList()..sort(),
      'assignments': {for (final d in _weekdays) '$d': _assignments['$d']},
      'active': _active,
      'reminder_time':
          '${_clock.hour.toString().padLeft(2, '0')}:${_clock.minute.toString().padLeft(2, '0')}',
    };
    final saved = await store.run(
      (api) => api.saveDuty(data, id: widget.duty?['id'] as int?),
      mutation: true,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = ref.read(dutiesStoreProvider).error ?? 'Не удалось сохранить.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(familyStoreProvider).members;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          widget.duty == null ? 'Новое дежурство' : 'Изменить дежурство',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _title,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Что нужно сделать',
                    ),
                    maxLength: 200,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Введите название'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  const Text('Дни недели и ответственные'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(weekdayLabels[d - 1]),
                          selected: _weekdays.contains(d),
                          onSelected: _busy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    _weekdays.add(d);
                                  } else {
                                    _weekdays.remove(d);
                                  }
                                }),
                        ),
                    ],
                  ),
                  for (final day in (_weekdays.toList()..sort()))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('assignment-$day-${members.length}'),
                        initialValue:
                            members.any((m) => m.id == _assignments['$day'])
                            ? _assignments['$day'] as int
                            : 0,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: weekdayLabels[day - 1],
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('Без назначения'),
                          ),
                          for (final m in members)
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                        ],
                        onChanged: _busy
                            ? null
                            : (id) =>
                                  _assignments['$day'] = id == 0 ? null : id,
                      ),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Начало: ${formatDate(_start)}'),
                    onPressed: _busy || widget.duty != null
                        ? null
                        : () async {
                            final value = await showDatePicker(
                              context: context,
                              initialDate: _start,
                              firstDate: DateTime(
                                DateTime.now().year,
                                DateTime.now().month,
                                DateTime.now().day,
                              ),
                              lastDate: DateTime(2100),
                            );
                            if (value != null && mounted) {
                              setState(() => _start = value);
                            }
                          },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text('Напоминание: ${_clock.format(context)}'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final value = await showTimePicker(
                              context: context,
                              initialTime: _clock,
                            );
                            if (value != null && mounted) {
                              setState(() => _clock = value);
                            }
                          },
                  ),
                  TextFormField(
                    controller: _zone,
                    enabled: !_busy && widget.duty == null,
                    decoration: const InputDecoration(
                      labelText: 'Часовой пояс',
                      helperText: 'Например Europe/Moscow',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Укажите часовой пояс'
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Дежурство активно'),
                    value: _active,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _active = v),
                  ),
                  const Text(
                    'Ответственный может быть без аккаунта. Изменения расписания и пауза действуют с завтрашнего дня; прошлые назначения сохраняются.',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
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
            onPressed: _busy || members.isEmpty ? null : _save,
            child: Text(_busy ? 'Сохранение…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

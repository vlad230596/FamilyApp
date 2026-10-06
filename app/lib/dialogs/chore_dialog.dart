import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/models/chore.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/chore_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/utils/dates.dart';

Future<void> showChoreDialog(BuildContext context, {Chore? chore}) =>
    showDialog<void>(
      context: context,
      builder: (_) => ChoreDialog(chore: chore),
    );

class ChoreDialog extends ConsumerStatefulWidget {
  const ChoreDialog({super.key, this.chore});
  final Chore? chore;
  @override
  ConsumerState<ChoreDialog> createState() => _ChoreDialogState();
}

class _ChoreDialogState extends ConsumerState<ChoreDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.chore?.title);
  late final _interval = TextEditingController(
    text: '${widget.chore?.intervalDays ?? 1}',
  );
  late final _zone = TextEditingController(
    text: widget.chore?.timezone ?? 'Europe/Moscow',
  );
  late var _start = widget.chore?.startDate ?? DateTime.now();
  late var _clock = widget.chore == null
      ? const TimeOfDay(hour: 23, minute: 0)
      : TimeOfDay(
          hour: int.parse(widget.chore!.reminderTime.split(':')[0]),
          minute: int.parse(widget.chore!.reminderTime.split(':')[1]),
        );
  late var _memberId =
      widget.chore?.responsibleMemberId ??
      ref.read(authStoreProvider).member?.id;
  late final _weekdays = widget.chore?.weekdays.toSet() ?? <int>{};
  late var _weekdayMode = _weekdays.isNotEmpty;
  late var _active = widget.chore?.active ?? true;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.chore == null) _loadZone();
  }

  Future<void> _loadZone() async {
    try {
      final zone = await ref.read(choreNotificationsProvider).deviceTimezone();
      if (mounted && _zone.text == 'Europe/Moscow') _zone.text = zone;
    } catch (_) {
      // The timezone remains editable if the device cannot provide one.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _interval.dispose();
    _zone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_weekdayMode && _weekdays.isEmpty) {
      setState(() => _error = 'Выберите хотя бы один день недели.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(choreStoreProvider.notifier);
    final success = await controller.save({
      'title': _title.text.trim(),
      'responsible_member_id': _memberId,
      'start_date': dateToIso(_start),
      'interval_days': _weekdayMode ? 1 : int.parse(_interval.text),
      'weekdays': _weekdayMode ? (_weekdays.toList()..sort()) : <int>[],
      'reminder_time':
          '${_clock.hour.toString().padLeft(2, '0')}:${_clock.minute.toString().padLeft(2, '0')}',
      'timezone': _zone.text.trim(),
      'active': _active,
    }, id: widget.chore?.id);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error =
            ref.read(choreStoreProvider).error ??
            'Не удалось сохранить задачу. Повторите попытку.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref
        .watch(familyStoreProvider)
        .members
        .where((member) => member.hasAccount)
        .toList();
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          widget.chore == null ? 'Регулярная задача' : 'Изменить задачу',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  TextFormField(
                    controller: _title,
                    enabled: !_busy,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Что проверять',
                      hintText: 'Посудомойка запущена?',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Введите название'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue:
                        members.any((member) => member.id == _memberId)
                        ? _memberId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Ответственный',
                    ),
                    items: members
                        .map(
                          (member) => DropdownMenuItem(
                            value: member.id,
                            child: Text(
                              member.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _memberId = value),
                    validator: (value) => value == null
                        ? 'Выберите участника с доступом в приложение'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Уведомление и право ответить получает только этот участник.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<bool>(
                    initialValue: _weekdayMode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Повторение'),
                    items: const [
                      DropdownMenuItem(
                        value: false,
                        child: Text('Каждые N дней'),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text('По дням недели'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _weekdayMode = value!),
                  ),
                  const SizedBox(height: 12),
                  if (!_weekdayMode)
                    TextFormField(
                      controller: _interval,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Интервал в днях',
                        helperText: '1 — ежедневно, 7 — раз в неделю',
                      ),
                      validator: (value) {
                        final n = int.tryParse(value ?? '');
                        return n == null || n < 1 || n > 365
                            ? 'От 1 до 365 дней'
                            : null;
                      },
                    ),
                  if (_weekdayMode)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var day = 1; day <= 7; day++)
                          FilterChip(
                            label: Text(weekdayLabels[day - 1]),
                            selected: _weekdays.contains(day),
                            onSelected: _busy
                                ? null
                                : (selected) => setState(() {
                                    if (selected) {
                                      _weekdays.add(day);
                                    } else {
                                      _weekdays.remove(day);
                                    }
                                  }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      'Начало: ${_start.day.toString().padLeft(2, '0')}.${_start.month.toString().padLeft(2, '0')}.${_start.year}',
                    ),
                    onPressed: _busy
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _start,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (date != null && mounted) {
                              setState(() => _start = date);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text('Напоминание: ${_clock.format(context)}'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final clock = await showTimePicker(
                              context: context,
                              initialTime: _clock,
                              builder: (context, child) => MediaQuery(
                                data: MediaQuery.of(
                                  context,
                                ).copyWith(alwaysUse24HourFormat: true),
                                child: child!,
                              ),
                            );
                            if (clock != null && mounted) {
                              setState(() => _clock = clock);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _zone,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Часовой пояс',
                      helperText: 'Например, Europe/Moscow',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Укажите часовой пояс'
                        : null,
                  ),
                  if (widget.chore != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Задача активна'),
                      value: _active,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _active = value),
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

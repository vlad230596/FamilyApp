import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/dialogs/duty_dialog.dart';
import 'package:familyapp/dialogs/household_action_dialog.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/state/household_store.dart';
import 'package:familyapp/utils/dates.dart';

class DutiesPage extends ConsumerStatefulWidget {
  const DutiesPage({super.key});
  @override
  ConsumerState<DutiesPage> createState() => _DutiesPageState();
}

class _DutiesPageState extends ConsumerState<DutiesPage> {
  var _day = dateOnly(DateTime.now());
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dutiesStoreProvider);
    final store = ref.read(dutiesStoreProvider.notifier);
    final parent = ref.watch(authStoreProvider).isParent;
    final items = state
        .rows('occurrences')
        .where((o) => o['occurrence_date'] == dateToIso(_day))
        .toList();
    final pending = state
        .rows('occurrences')
        .where((o) => o['status'] == 'pending' && o['away'] != true)
        .toList();
    final suggestion = state.data['suggestion'] as Map<String, dynamic>?;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: RefreshIndicator(
          onRefresh: store.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (state.busy) const LinearProgressIndicator(),
              if (state.error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(state.error!),
                  ),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text('Дежурства за ${formatDate(_day)}'),
                onPressed: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (day != null && mounted) setState(() => _day = day);
                },
              ),
              if (items.isEmpty && !state.busy)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'На этот день дежурств нет.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final item in items) _occurrenceCard(item, state, parent),
              if (parent && pending.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Ждут подтверждения (${pending.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                for (final item in pending.where(
                  (o) => o['occurrence_date'] != dateToIso(_day),
                ))
                  _occurrenceCard(item, state, parent),
              ],
              ExpansionTile(
                title: const Text('Баланс, оценки и расписание'),
                leading: const Icon(Icons.tune_outlined),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Баланс и оценки',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const Text(
                    'Пропуск: +1 день долга. Выполнение за другого: −1 день. Сегодняшний день ещё не считается пропущенным. Оценки не меняют баланс.',
                  ),
                  if (suggestion != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Предлагаем компенсацию: ${suggestion['name']} — долг ${suggestion['debt']} дн.',
                      ),
                    ),
                  for (final stat in state.rows('statistics'))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${stat['name']} · баланс ${stat['debt']} дн.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Пропущено: ${stat['missed']} · За других: ${stat['covered']} · Выполнено: ${stat['completed']}',
                            ),
                            Text(
                              'Плохо: ${stat['bad']} · Нормально: ${stat['normal']} · Отлично: ${stat['great']}',
                            ),
                            if (stat['pending'] != 0)
                              Text('Ждёт подтверждения: ${stat['pending']}'),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Отсутствие семьи',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (parent)
                    TextButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => showHouseholdAction(
                              context,
                              HouseholdAction.away,
                            ),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить период отсутствия'),
                    ),
                  for (final period in state.rows('away_periods'))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatDate(DateTime.parse(period['start_date']))} — ${formatDate(DateTime.parse(period['end_date']))}',
                            ),
                            if (parent)
                              TextButton(
                                onPressed: state.busy
                                    ? null
                                    : () => store.run(
                                        (api) =>
                                            api.cancelAway(period['id'] as int),
                                        mutation: true,
                                      ),
                                child: const Text('Отменить период'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Расписание',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  for (final duty in state.rows('duties'))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              duty['title'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${duty['active'] == true ? 'Активно' : 'Приостановлено'} · ${duty['reminder_time']} · ${duty['timezone']}',
                            ),
                            Text(
                              'Текущая версия с ${formatDate(DateTime.parse(duty['effective_date']))}',
                            ),
                            if (parent)
                              TextButton.icon(
                                onPressed: state.busy
                                    ? null
                                    : () => showDutyDialog(context, duty: duty),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Изменить расписание'),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _occurrenceCard(
    Map<String, dynamic> item,
    HouseholdState state,
    bool parent,
  ) {
    final status = item['away'] == true
        ? 'Семья отсутствует'
        : switch (item['status']) {
            'pending' => 'Ждёт подтверждения',
            'confirmed' => 'Выполнено',
            'rejected' => 'Вернули на доработку',
            _ => 'Не выполнено',
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['title'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${formatDate(DateTime.parse(item['occurrence_date']))} · ${item['assigned_name'] ?? 'Без назначения'}',
            ),
            Text(status),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Кто выполнил и оценка'),
              children: [
                if (item['performer_name'] != null)
                  Text(
                    'Выполнил: ${item['performer_name']} · Отметил: ${item['marked_by_name']}',
                  ),
                if (item['rating'] != null)
                  Text(
                    'Оценка: ${ratingLabels[item['rating']]} · Подтвердил: ${item['confirmed_by_name']}',
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                if (item['away'] != true &&
                    (item['status'] == 'open' || item['status'] == 'rejected'))
                  FilledButton.icon(
                    onPressed: state.busy
                        ? null
                        : () => showHouseholdAction(
                            context,
                            HouseholdAction.complete,
                            item: item,
                          ),
                    icon: const Icon(Icons.check),
                    label: const Text('Выполнено'),
                  ),
                if (parent &&
                    item['status'] == 'pending' &&
                    item['away'] != true)
                  FilledButton(
                    onPressed: state.busy
                        ? null
                        : () => showHouseholdAction(
                            context,
                            HouseholdAction.review,
                            item: item,
                          ),
                    child: const Text('Рассмотреть'),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text('История отметок'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => DutyHistoryDialog(item: item),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DutyHistoryDialog extends ConsumerStatefulWidget {
  const DutyHistoryDialog({super.key, required this.item});
  final Map<String, dynamic> item;
  @override
  ConsumerState<DutyHistoryDialog> createState() => _DutyHistoryDialogState();
}

class _DutyHistoryDialogState extends ConsumerState<DutyHistoryDialog> {
  late final _future = ref
      .read(apiClientProvider)
      .dutyHistory(widget.item['id'] as int);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('История отметок'),
    content: SizedBox(
      width: 480,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Не удалось загрузить историю.');
          }
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data!.isEmpty) return const Text('Отметок пока нет.');
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final event in snapshot.data!)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(switch (event['snapshot']['status']) {
                      'confirmed' => 'Подтверждено',
                      'rejected' => 'Отклонено',
                      _ => 'Отправлено на подтверждение',
                    }),
                    subtitle: Text(
                      '${DateTime.parse(event['created_at']).toLocal()} · ${event['actor_name']}\nВыполнил: ${event['snapshot']['performer_name'] ?? '—'}\n${event['snapshot']['title']}${event['snapshot']['rating'] == null ? '' : ' · ${ratingLabels[event['snapshot']['rating']]}'}',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  );
}

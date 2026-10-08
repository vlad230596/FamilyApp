import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/dialogs/chore_dialog.dart';
import 'package:familyapp/models/chore.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/chore_store.dart';
import 'package:familyapp/state/family_store.dart';

class ChoresPage extends ConsumerWidget {
  const ChoresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(choreStoreProvider);
    final auth = ref.watch(authStoreProvider);
    final controller = ref.read(choreStoreProvider.notifier);
    final notifications = ref.read(choreNotificationsProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (state.busy) const LinearProgressIndicator(),
              if (state.error != null || state.reminderError != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(state.error ?? state.reminderError!),
                  ),
                ),
              if (notifications.supported)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Личные напоминания о проверках'),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Разрешить уведомления'),
                          onPressed: () async {
                            try {
                              final allowed = await notifications
                                  .requestPermission();
                              await controller.refresh();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      allowed
                                          ? 'Уведомления разрешены. Без разрешения на точные напоминания возможна задержка.'
                                          : 'Разрешите уведомления в настройках Android.',
                                    ),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Не удалось включить уведомления. Проверьте настройки Android.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              if (!notifications.supported)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('Уведомления — в приложении Android'),
                ),
              if (state.chores.isEmpty && !state.busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      const Icon(Icons.task_alt, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Регулярных задач пока нет',
                        style: TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        auth.isParent
                            ? 'Добавьте проверку и назначьте ответственного.'
                            : 'Назначенные вам задачи появятся здесь.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              for (final chore in state.chores)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chore.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${chore.responsibleName} · ${chore.reminderTime}',
                        ),
                        const SizedBox(height: 12),
                        if (!chore.active) const Text('Приостановлена'),
                        if (chore.dueDate != null)
                          Text(
                            'Проверка ${_dateLabel(chore.dueDate!)}: ${chore.dueAnswer == null
                                ? 'ожидает ответа'
                                : chore.dueAnswer!
                                ? 'Да'
                                : 'Нет'}',
                          ),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Расписание и детали'),
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(chore.scheduleLabel),
                              subtitle: Text(
                                '${chore.reminderTime} · ${chore.timezone}',
                              ),
                            ),
                            if (chore.nextAt != null)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Следующая: ${_dateLabel(chore.nextAt!.substring(0, 10))}',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (chore.active &&
                                chore.responsibleMemberId == auth.member?.id &&
                                chore.dueDate != null &&
                                chore.dueAnswer == null) ...[
                              FilledButton.icon(
                                onPressed: state.busy
                                    ? null
                                    : () => controller.answer(
                                        chore.id,
                                        chore.dueDate!,
                                        true,
                                        chore.revision,
                                      ),
                                icon: const Icon(Icons.check),
                                label: const Text('Да'),
                              ),
                              OutlinedButton.icon(
                                onPressed: state.busy
                                    ? null
                                    : () => controller.answer(
                                        chore.id,
                                        chore.dueDate!,
                                        false,
                                        chore.revision,
                                      ),
                                icon: const Icon(Icons.close),
                                label: const Text('Нет'),
                              ),
                            ],
                            TextButton.icon(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    ChoreHistoryDialog(chore: chore),
                              ),
                              icon: const Icon(Icons.history),
                              label: const Text('История'),
                            ),
                            if (auth.isParent)
                              TextButton.icon(
                                onPressed: state.busy
                                    ? null
                                    : () => showChoreDialog(
                                        context,
                                        chore: chore,
                                      ),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Изменить'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dateLabel(String value) =>
    '${value.substring(8, 10)}.${value.substring(5, 7)}.${value.substring(0, 4)}';

class ChoreHistoryDialog extends ConsumerStatefulWidget {
  const ChoreHistoryDialog({super.key, required this.chore});
  final Chore chore;
  @override
  ConsumerState<ChoreHistoryDialog> createState() => _ChoreHistoryDialogState();
}

class _ChoreHistoryDialogState extends ConsumerState<ChoreHistoryDialog> {
  late final _history = ref
      .read(apiClientProvider)
      .choreHistory(widget.chore.id);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('История: ${widget.chore.title}'),
    content: SizedBox(
      width: 480,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _history,
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
          if (snapshot.data!.isEmpty) return const Text('Ответов пока нет.');
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final answer in snapshot.data!)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      answer['answer'] == true
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                    ),
                    title: Text(
                      '${_dateLabel(answer['occurrence_date'] as String)} — ${answer['answer'] == true ? 'Да' : 'Нет'}',
                    ),
                    subtitle: Text(
                      '${answer['title']}\n${answer['actor_name']} · ${DateTime.parse(answer['created_at'] as String).toLocal()}',
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

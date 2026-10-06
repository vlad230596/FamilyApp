import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/models/chore.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';

final choreStoreProvider = NotifierProvider<ChoreStore, ChoreState>(
  ChoreStore.new,
);

class ChoreState {
  const ChoreState({
    this.chores = const [],
    this.busy = false,
    this.error,
    this.reminderError,
  });
  final List<Chore> chores;
  final bool busy;
  final String? error;
  final String? reminderError;
}

class ChoreStore extends Notifier<ChoreState> {
  var _generation = 0;

  @override
  ChoreState build() {
    ref.watch(authStoreProvider.select((state) => state.member?.id));
    _generation++;
    Future.microtask(refresh);
    return const ChoreState();
  }

  Future<void> refresh() => _run(() async {});

  Future<bool> save(Map<String, dynamic> data, {int? id}) => _run(
    () => ref.read(apiClientProvider).saveChore(data, id: id),
    mutation: true,
  );

  Future<bool> answer(int id, String date, bool answer, int revision) => _run(
    () => ref.read(apiClientProvider).answerChore(id, date, answer, revision),
    mutation: true,
  );

  Future<bool> _run(
    Future<void> Function() action, {
    bool mutation = false,
  }) async {
    if (state.busy) return false;
    final generation = _generation;
    final memberId = ref.read(authStoreProvider).member?.id;
    if (memberId == null) return false;
    state = ChoreState(chores: state.chores, busy: true);
    var saved = false;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        ref.read(authStoreProvider).member?.id == memberId;
    try {
      await action();
      saved = mutation;
      final api = ref.read(apiClientProvider);
      final chores = await api.listChores();
      if (!current()) return false;
      String? reminderError;
      try {
        final reminders = await api.choreReminders();
        if (!current()) return false;
        await ref
            .read(choreNotificationsProvider)
            .synchronize(
              reminders,
              retained: {
                for (final chore in chores)
                  if (chore.active &&
                      chore.responsibleMemberId == memberId &&
                      chore.dueDate != null &&
                      chore.dueAnswer == null)
                    notificationTag({
                      'chore_id': chore.id,
                      'occurrence_date': chore.dueDate,
                      'revision': chore.revision,
                      'member_id': memberId,
                    }),
              },
            );
      } catch (_) {
        reminderError =
            'Не удалось обновить напоминания. Попробуйте обновить список.';
      }
      if (!current()) return false;
      state = ChoreState(chores: chores, reminderError: reminderError);
      return true;
    } catch (error) {
      if (current()) {
        state = ChoreState(
          chores: state.chores,
          error: saved
              ? 'Изменения сохранены, но список не обновился. Нажмите «Обновить».'
              : error.toString().replaceFirst('Exception: ', ''),
        );
      }
      return saved && current();
    }
  }
}

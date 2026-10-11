import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/chore_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/services/local_storage.dart';
import 'package:familyapp/services/shopping_sync.dart';
import 'package:familyapp/services/background_reminder_sync.dart';

final dutiesStoreProvider = NotifierProvider<DutiesStore, HouseholdState>(
  DutiesStore.new,
);
final shoppingStoreProvider = NotifierProvider<ShoppingStore, HouseholdState>(
  ShoppingStore.new,
);

class HouseholdState {
  const HouseholdState({
    this.data = const {},
    this.busy = false,
    this.error,
    this.offline = false,
    this.syncing = false,
    this.pending = 0,
    this.lastSync,
    this.conflicts = const [],
    this.blocked = const [],
    this.notices = const [],
  });
  final Map<String, dynamic> data;
  final bool busy;
  final String? error;
  final bool offline, syncing;
  final int pending;
  final DateTime? lastSync;
  final List<Map<String, dynamic>> conflicts, blocked;
  final List<String> notices;
  List<Map<String, dynamic>> rows(String key) =>
      (data[key] as List? ?? []).cast<Map<String, dynamic>>();
}

abstract class HouseholdStore extends Notifier<HouseholdState> {
  int _generation = 0;
  Future<Map<String, dynamic>> load(ApiClient api);
  @override
  HouseholdState build() {
    ref.watch(authStoreProvider.select((s) => s.member?.id));
    _generation++;
    Future.microtask(refresh);
    return const HouseholdState();
  }

  Future<void> refresh() async {
    await run((_) async {});
  }

  Future<bool> run(
    Future<void> Function(ApiClient) action, {
    bool mutation = false,
  }) async {
    if (state.busy || ref.read(authStoreProvider).member == null) return false;
    final generation = _generation;
    final member = ref.read(authStoreProvider).member!.id;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        ref.read(authStoreProvider).member?.id == member;
    state = HouseholdState(data: state.data, busy: true);
    var saved = false;
    try {
      final api = ref.read(apiClientProvider);
      await action(api);
      saved = mutation;
      final data = await load(api);
      if (!current()) return false;
      state = HouseholdState(data: data);
      if (mutation && this is DutiesStore) {
        await ref.read(choreStoreProvider.notifier).refresh();
      }
      return current();
    } catch (error) {
      if (current()) {
        state = HouseholdState(
          data: state.data,
          error: saved
              ? 'Изменения сохранены, но список не обновился. Нажмите «Обновить».'
              : error.toString().replaceFirst('Exception: ', ''),
        );
      }
      return saved && current();
    }
  }
}

class DutiesStore extends HouseholdStore {
  @override
  Future<Map<String, dynamic>> load(ApiClient api) => api.duties();
}

class ShoppingStore extends HouseholdStore {
  int? selectedListId;
  ShoppingSync? _local;
  int _session = 0;
  bool _managing = false;

  @override
  HouseholdState build() {
    final owner = ref.watch(
      authStoreProvider.select(
        (s) =>
            (s.account?['user']?['id'], s.account?['family_id'], s.member?.id),
      ),
    );
    final generation = ++_session;
    selectedListId = null;
    _managing = false;
    _local = null;
    bool current() =>
        ref.mounted &&
        generation == _session &&
        ref.read(authStoreProvider).status == AuthStatus.signedIn;
    if (owner.$1 is int && owner.$2 is int && owner.$3 is int) {
      final local = ShoppingSync(
        storage: ref.read(localStorageProvider),
        key: shoppingStorageKey(
          owner.$1 as int,
          owner.$2 as int,
          owner.$3 as int,
        ),
        api: ref.read(apiClientProvider),
        familyId: owner.$2 as int,
        memberId: owner.$3 as int,
        memberName: ref.read(authStoreProvider).member!.name,
        current: current,
        changed: () {
          if (current()) _publish();
        },
      );
      _local = local;
      Future.microtask(() async {
        await local.restore();
        if (current() && local.operations.isNotEmpty) _scheduleBackground();
      });
      var active = true;
      final lifecycle = AppLifecycleListener(
        onPause: () => active = false,
        onResume: () {
          active = true;
          if (current()) unawaited(local.synchronize());
        },
      );
      final timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (active &&
            current() &&
            (local.offline || local.operations.isNotEmpty)) {
          unawaited(local.synchronize());
        }
      });
      ref.onDispose(() {
        timer.cancel();
        lifecycle.dispose();
      });
    }
    return const HouseholdState(busy: true);
  }

  void _publish() {
    final local = _local;
    if (local == null) return;
    if (selectedListId != null &&
        !local.lists.any((row) => row['id'] == selectedListId)) {
      selectedListId = null;
    }
    state = HouseholdState(
      data: local.view(selectedListId),
      busy: !local.ready || local.saving || _managing,
      error: local.error,
      offline: local.offline,
      syncing: local.syncing,
      pending: local.operations.length,
      lastSync: DateTime.tryParse(
        local.document['last_sync'] as String? ?? '',
      )?.toLocal(),
      conflicts: List.of(local.conflicts),
      blocked: local.operations
          .where((op) => op['blocked_error'] != null)
          .toList(),
      notices: (local.document['notices'] as List).cast<String>(),
    );
  }

  @override
  Future<void> refresh() async => _local?.synchronize();

  Future<bool> add(Map<String, dynamic> values) async {
    final local = _local;
    if (local == null || state.busy) return false;
    final listId = state.data['list_id'];
    if (listId == null) {
      local.error =
          'Сначала загрузите список покупок при подключённом интернете.';
      _publish();
      return false;
    }
    final saved = await local.enqueue({
      'kind': 'add',
      'list_id': listId,
      ...values,
    });
    if (saved) _scheduleBackground();
    return saved;
  }

  Future<bool> buy(Map<String, dynamic> item, int? days) async {
    final local = _local;
    if (local == null || state.busy) return false;
    final saved = await local.enqueue({
      'kind': 'buy',
      'return_in_days': days,
      if (item['local_operation_id'] != null)
        'add_operation_id': item['local_operation_id']
      else
        'item_key': item['item_key'],
    });
    if (saved) _scheduleBackground();
    return saved;
  }

  Future<void> resolve(Map<String, dynamic> conflict, bool useLocal) async {
    final saved = await _local?.enqueue({
      'kind': 'resolve',
      'conflict_operation_id': conflict['operation_id'],
      'choice': useLocal ? 'local' : 'server',
    });
    if (saved == true) _scheduleBackground();
  }

  Future<void> discardBlocked(String id) async {
    await _local?.discardBlocked(id);
    await refresh();
  }

  Future<void> dismissNotice(String notice) async =>
      _local?.dismissNotice(notice);

  void _scheduleBackground() {
    final auth = ref.read(authStoreProvider);
    final local = _local;
    if (local == null || auth.member == null) return;
    unawaited(
      ref
          .read(backgroundReminderSyncProvider)
          .scheduleShopping(auth.member!.id, local.familyId, local.key)
          .catchError((Object _) {}),
    );
  }

  /// List management and returning history still require a server connection.
  @override
  Future<bool> run(
    Future<void> Function(ApiClient) action, {
    bool mutation = false,
  }) async {
    final local = _local;
    if (local == null || state.busy) return false;
    _managing = true;
    _publish();
    var saved = false;
    try {
      await action(ref.read(apiClientProvider));
      saved = true;
      await local.synchronize();
      return local.current();
    } catch (error) {
      local.error = error.toString().replaceFirst('Exception: ', '');
      return saved && local.current();
    } finally {
      if (local.current()) {
        _managing = false;
        _publish();
      }
    }
  }

  Future<void> selectList(int id) async {
    if (state.busy) return;
    selectedListId = id;
    _publish();
  }

  @override
  Future<Map<String, dynamic>> load(ApiClient api) => selectedListId == null
      ? api.shopping()
      : api.shoppingList(selectedListId!);
}

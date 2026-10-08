import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';

final shoppingStoreProvider = NotifierProvider<ShoppingStore, HouseholdState>(
  ShoppingStore.new,
);

class HouseholdState {
  const HouseholdState({this.data = const {}, this.busy = false, this.error});
  final Map<String, dynamic> data;
  final bool busy;
  final String? error;
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

class ShoppingStore extends HouseholdStore {
  int? selectedListId;

  @override
  HouseholdState build() {
    selectedListId = null;
    return super.build();
  }

  Future<void> selectList(int id) async {
    if (state.busy) return;
    selectedListId = id;
    await refresh();
  }

  @override
  Future<Map<String, dynamic>> load(ApiClient api) => selectedListId == null
      ? api.shopping()
      : api.shoppingList(selectedListId!);
}

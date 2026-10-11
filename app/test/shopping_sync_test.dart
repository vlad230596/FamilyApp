import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/services/local_storage.dart';
import 'package:familyapp/services/shopping_sync.dart';

class MemoryLocalStorage extends LocalStorage {
  final values = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Disk full');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class ShoppingApi extends ApiClient {
  ShoppingApi() : super('http://unused.invalid');
  bool online = true, loseNextResponse = false, reject = false;
  Map<String, dynamic>? forcedResult;
  void Function()? afterCommand;
  int selectedFamily = 1;
  Completer<void>? snapshotGate;
  final commands = <Map<String, dynamic>>[];
  final receipts = <String, Map<String, dynamic>>{};
  final items = <Map<String, dynamic>>[
    for (var i = 1; i <= 50; i++)
      {
        'id': i,
        'item_key': 'item_$i',
        'name': 'Товар $i',
        'category': '',
        'urgency': 'week',
        'list_id': 1,
      },
  ];
  final purchases = <Map<String, dynamic>>[];
  final lists = [
    {'id': 1, 'name': 'Продукты', 'is_main': 1},
    {'id': 2, 'name': 'Дача', 'is_main': 0},
  ];
  void check() {
    if (!online) throw ServerUnavailableException();
  }

  @override
  Future<Map<String, dynamic>> accountState() async {
    check();
    return {
      'family_id': selectedFamily,
      'member': {'id': 1},
    };
  }

  @override
  Future<Map<String, dynamic>> shoppingSnapshot() async {
    check();
    if (snapshotGate != null) await snapshotGate!.future;
    return copyShoppingData({
      'lists': lists,
      'snapshots': [
        {'list_id': 1, 'items': items, 'purchases': purchases},
        {
          'list_id': 2,
          'items': [
            {
              'id': 100,
              'item_key': 'dacha',
              'name': 'Вода',
              'urgency': 'week',
              'category': '',
            },
          ],
          'purchases': [],
        },
      ],
    });
  }

  @override
  Future<Map<String, dynamic>> syncShopping(
    Map<String, dynamic> operation,
  ) async {
    check();
    commands.add(copyShoppingData(operation));
    afterCommand?.call();
    if (forcedResult != null) return forcedResult!;
    if (reject) throw ApiException(400, 'Некорректное изменение');
    final id = operation['operation_id'] as String;
    final old = receipts[id];
    if (old != null) return old;
    late Map<String, dynamic> result;
    if (operation['kind'] == 'add') {
      items.add({
        'id': 51,
        'item_key': id,
        'name': operation['name'],
        'category': operation['category'],
        'urgency': operation['urgency'],
        'list_id': operation['list_id'],
      });
      result = {'status': 'applied', 'item_key': id};
    } else if (operation['kind'] == 'buy') {
      final key =
          operation['item_key'] ??
          receipts[operation['add_operation_id']]?['item_key'];
      final item = items.where((item) => item['item_key'] == key).firstOrNull;
      if (item != null) {
        items.remove(item);
        purchases.add({
          ...item,
          'id': purchases.length + 1,
          'bought_at': operation['occurred_at'],
          'bought_by_name': 'Мама',
        });
        result = {'status': 'applied'};
      } else {
        result = {'status': 'already_bought', 'name': 'Молоко'};
      }
    } else {
      result = {'status': 'applied'};
    }
    receipts[id] = result;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw ServerUnavailableException();
    }
    return result;
  }
}

ShoppingSync engine(
  MemoryLocalStorage storage,
  ShoppingApi api, {
  String key = 'family1',
  bool Function()? current,
}) => ShoppingSync(
  storage: storage,
  key: key,
  api: api,
  familyId: 1,
  memberId: 1,
  memberName: 'Мама',
  current: current ?? () => true,
  changed: () {},
);

Future<void> finish(ShoppingSync local) async {
  await Future<void>.delayed(Duration.zero);
  await local.synchronize();
}

void main() {
  test(
    'receipt write failure keeps command durable and retry acknowledges it',
    () async {
      final storage = MemoryLocalStorage();
      final api = ShoppingApi();
      final local = engine(storage, api);
      await local.restore();
      api.afterCommand = () => storage.failWrites = true;
      await local.enqueue({
        'kind': 'buy',
        'item_key': 'item_1',
        'return_in_days': null,
      });
      await Future<void>.delayed(Duration.zero);
      expect(local.operations.length, 1);
      expect(api.purchases.length, 1);
      expect(
        (jsonDecode(storage.values['family1']!)['operations'] as List).length,
        1,
      );
      storage.failWrites = false;
      api.afterCommand = null;
      await local.synchronize();
      expect(local.operations, isEmpty);
      expect(api.purchases.length, 1);
    },
  );

  test(
    'return-period conflict survives restart and explicit resolution',
    () async {
      final storage = MemoryLocalStorage();
      final api = ShoppingApi();
      final local = engine(storage, api);
      await local.restore();
      api.forcedResult = {
        'status': 'conflict',
        'name': 'Молоко',
        'purchase_id': 1,
        'return_in_days': 7,
        'requested_days': 3,
        'can_change': true,
      };
      await local.enqueue({
        'kind': 'buy',
        'item_key': 'item_1',
        'return_in_days': 3,
      });
      await finish(local);
      expect(local.operations, isEmpty);
      expect(local.conflicts.single['requested_days'], 3);
      final restored = engine(storage, api);
      await restored.restore();
      final conflict = restored.conflicts.single;
      api.forcedResult = {'status': 'applied'};
      await restored.enqueue({
        'kind': 'resolve',
        'conflict_operation_id': conflict['operation_id'],
        'choice': 'local',
      });
      await finish(restored);
      expect(restored.conflicts, isEmpty);
      expect(api.commands.last['choice'], 'local');
    },
  );
  test(
    '50-item basement scenario survives restart and sends six actions',
    () async {
      final storage = MemoryLocalStorage();
      final api = ShoppingApi();
      final first = engine(storage, api);
      await first.restore();
      expect((first.view(null)['items'] as List).length, 50);
      api.online = false;
      expect(
        await first.enqueue({
          'kind': 'add',
          'list_id': 1,
          'name': 'Хлеб',
          'category': '',
          'urgency': 'week',
        }),
        isTrue,
      );
      await finish(first);
      for (var i = 1; i <= 5; i++) {
        expect(
          await first.enqueue({
            'kind': 'buy',
            'item_key': 'item_$i',
            'return_in_days': null,
          }),
          isTrue,
        );
      }
      await finish(first);
      final reopened = engine(storage, api);
      await reopened.restore();
      expect(reopened.offline, isTrue);
      expect(reopened.operations.length, 6);
      expect((reopened.view(null)['items'] as List).length, 46);
      expect((reopened.view(null)['purchases'] as List).length, 5);
      expect((reopened.view(2)['items'] as List).single['name'], 'Вода');
      api.online = true;
      await reopened.synchronize();
      expect(reopened.operations, isEmpty);
      expect(reopened.offline, isFalse);
      expect(api.items.length, 46);
      expect(api.purchases.length, 5);
      expect(api.receipts.length, 6);
    },
  );

  test(
    'offline-created item can be purchased before it has a server ID',
    () async {
      final storage = MemoryLocalStorage();
      final api = ShoppingApi();
      final local = engine(storage, api);
      await local.restore();
      api.online = false;
      await local.enqueue({
        'kind': 'add',
        'list_id': 1,
        'name': 'Хлеб',
        'category': '',
        'urgency': 'week',
      });
      final item = (local.view(null)['items'] as List).last;
      await local.enqueue({
        'kind': 'buy',
        'add_operation_id': item['local_operation_id'],
        'return_in_days': 7,
      });
      await finish(local);
      expect((local.view(null)['items'] as List).length, 50);
      api.online = true;
      await local.synchronize();
      expect(local.operations, isEmpty);
      expect(api.items.length, 50);
      expect(api.purchases.single['name'], 'Хлеб');
    },
  );

  test(
    'lost response leaves durable command and replay does not duplicate it',
    () async {
      final storage = MemoryLocalStorage();
      final api = ShoppingApi();
      final local = engine(storage, api);
      await local.restore();
      api.loseNextResponse = true;
      await local.enqueue({
        'kind': 'add',
        'list_id': 1,
        'name': 'Хлеб',
        'category': '',
        'urgency': 'week',
      });
      await Future<void>.delayed(Duration.zero);
      expect(local.operations.length, 1);
      expect(api.items.length, 51);
      final pending = storage.values['family1'];
      final restored = engine(storage, api);
      await restored.restore();
      expect(restored.operations, isEmpty);
      expect(api.items.length, 51);
      expect(api.commands.length, 2);
      expect(api.commands[0], api.commands[1]);
      expect(pending, isNot(storage.values['family1']));
    },
  );

  test('storage failure never reports an unsaved edit as saved', () async {
    final storage = MemoryLocalStorage();
    final api = ShoppingApi();
    final local = engine(storage, api);
    await local.restore();
    storage.failWrites = true;
    expect(
      await local.enqueue({
        'kind': 'buy',
        'item_key': 'item_1',
        'return_in_days': null,
      }),
      isFalse,
    );
    expect(local.operations, isEmpty);
    expect(api.commands, isEmpty);
    expect((local.view(null)['items'] as List).length, 50);
    expect(local.error, contains('не сохранено'));
  });

  test('new edits during synchronization are retained and sent', () async {
    final storage = MemoryLocalStorage();
    final api = ShoppingApi();
    final local = engine(storage, api);
    await local.restore();
    api.snapshotGate = Completer<void>();
    await local.enqueue({
      'kind': 'buy',
      'item_key': 'item_1',
      'return_in_days': null,
    });
    await Future<void>.delayed(Duration.zero);
    await local.enqueue({
      'kind': 'buy',
      'item_key': 'item_2',
      'return_in_days': null,
    });
    api.snapshotGate!.complete();
    await finish(local);
    expect(local.operations, isEmpty);
    expect(api.purchases.length, 2);
  });

  test(
    'background replay keeps the local document for safe foreground reconciliation',
    () async {
      final storage = MemoryLocalStorage();
      final api = ShoppingApi();
      final local = engine(storage, api);
      await local.restore();
      api.online = false;
      await local.enqueue({
        'kind': 'buy',
        'item_key': 'item_1',
        'return_in_days': null,
      });
      await finish(local);
      final before = storage.values['family1'];
      api.online = true;
      expect(
        await replayShoppingInBackground(
          api: api,
          storage: storage,
          key: 'family1',
          familyId: 1,
          memberId: 1,
          current: () async => true,
        ),
        isTrue,
      );
      expect(api.purchases.length, 1);
      expect(storage.values['family1'], before);
      await local.synchronize();
      expect(local.operations, isEmpty);
      expect(api.purchases.length, 1);
    },
  );

  test(
    'wrong family and invalidated background context cannot send private commands',
    () async {
      final storage = MemoryLocalStorage();
      final api = ShoppingApi();
      final local = engine(storage, api);
      await local.restore();
      api.online = false;
      await local.enqueue({
        'kind': 'buy',
        'item_key': 'item_1',
        'return_in_days': null,
      });
      await finish(local);
      api.online = true;
      api.selectedFamily = 2;
      await local.synchronize();
      expect(api.commands, isEmpty);
      expect(local.operations.length, 1);
      expect(
        await replayShoppingInBackground(
          api: api,
          storage: storage,
          key: 'family1',
          familyId: 1,
          memberId: 1,
          current: () async => true,
        ),
        isTrue,
      );
      api.selectedFamily = 1;
      expect(
        await replayShoppingInBackground(
          api: api,
          storage: storage,
          key: 'family1',
          familyId: 1,
          memberId: 1,
          current: () async => false,
        ),
        isTrue,
      );
      expect(api.commands, isEmpty);
      final otherOwner = engine(storage, api, key: 'family2');
      expect(otherOwner.operations, isEmpty);
    },
  );

  test('rejected operation stays visible until explicitly discarded', () async {
    final storage = MemoryLocalStorage();
    final api = ShoppingApi();
    final local = engine(storage, api);
    await local.restore();
    api.reject = true;
    await local.enqueue({
      'kind': 'add',
      'list_id': 1,
      'name': 'Хлеб',
      'category': '',
      'urgency': 'week',
    });
    await Future<void>.delayed(Duration.zero);
    expect(local.operations.single['blocked_error'], 'Некорректное изменение');
    final saved =
        jsonDecode(storage.values['family1']!) as Map<String, dynamic>;
    expect((saved['operations'] as List).length, 1);
    await local.discardBlocked(
      local.operations.single['operation_id'] as String,
    );
    expect(local.operations, isEmpty);
    expect((local.view(null)['items'] as List).length, 50);
  });
}

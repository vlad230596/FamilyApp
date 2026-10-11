import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/services/local_storage.dart';

String newShoppingOperationId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Map<String, dynamic> copyShoppingData(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

String shoppingStorageKey(int userId, int familyId, int memberId) =>
    'shopping_v1_${userId}_${familyId}_$memberId';

/// Only the foreground writes this document. Background workers replay commands
/// without acknowledging them; server receipts make concurrent retries safe.
class ShoppingSync {
  ShoppingSync({
    required this.storage,
    required this.key,
    required this.api,
    required this.familyId,
    required this.memberId,
    required this.memberName,
    required this.current,
    required this.changed,
  });

  final LocalStorage storage;
  final String key;
  final ApiClient api;
  final int familyId;
  final int memberId;
  final String memberName;
  final bool Function() current;
  final void Function() changed;
  Map<String, dynamic> document = {
    'lists': [],
    'snapshots': [],
    'operations': [],
    'conflicts': [],
    'notices': [],
  };
  bool offline = false, syncing = false, saving = false, ready = false;
  String? error;
  Future<void> _writes = Future.value();
  Future<void>? _sync;

  List<Map<String, dynamic>> get operations =>
      (document['operations'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get conflicts =>
      (document['conflicts'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get lists =>
      (document['lists'] as List).cast<Map<String, dynamic>>();

  Future<void> restore() async {
    try {
      final saved = await storage.read(key);
      if (!current()) return;
      if (saved != null) document = jsonDecode(saved) as Map<String, dynamic>;
      offline = saved != null;
      ready = true;
      changed();
      await synchronize();
    } catch (_) {
      if (!current()) return;
      error =
          'Не удалось прочитать сохранённые покупки. Повторите открытие приложения.';
      changed();
    }
  }

  Future<void> _edit(void Function(Map<String, dynamic>) edit) {
    final next = _writes.then((_) async {
      if (!current()) return;
      final candidate = copyShoppingData(document);
      edit(candidate);
      await storage.write(key, jsonEncode(candidate));
      if (!current()) return;
      document = candidate;
      changed();
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<bool> enqueue(Map<String, dynamic> values) async {
    if (!ready || !current() || saving) return false;
    saving = true;
    error = null;
    changed();
    try {
      final operation = {
        'operation_id': newShoppingOperationId(),
        'family_id': familyId,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        ...values,
      };
      await _edit((data) {
        if (operation['kind'] == 'add') {
          operation['local_id'] = (data['next_local_id'] as int? ?? 0) - 1;
          data['next_local_id'] = operation['local_id'];
        }
        (data['operations'] as List).add(operation);
      });
      if (!current()) return false;
      unawaited(synchronize());
      return true;
    } catch (_) {
      error = 'Не удалось сохранить на устройстве. Изменение не сохранено.';
      return false;
    } finally {
      saving = false;
      if (current()) changed();
    }
  }

  Map<String, dynamic> view(int? selectedId) {
    final all = (document['snapshots'] as List).cast<Map<String, dynamic>>();
    final id =
        selectedId ??
        lists.where((row) => row['is_main'] == 1).firstOrNull?['id'] ??
        lists.firstOrNull?['id'];
    final base = all.where((row) => row['list_id'] == id).firstOrNull;
    final data = copyShoppingData(
      base ?? {'list_id': id, 'items': [], 'purchases': []},
    );
    data['lists'] = copyShoppingData({'value': lists})['value'];
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final purchases = (data['purchases'] as List).cast<Map<String, dynamic>>();
    String normalized(String name) => name
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase()
        .replaceAll('ё', 'е');
    const urgencies = ['background', 'week', 'urgent'];
    for (final op in operations) {
      if (op['kind'] == 'add' && op['list_id'] == id) {
        final existing = items
            .where(
              (item) =>
                  normalized(item['name'] as String) ==
                  normalized(op['name'] as String),
            )
            .firstOrNull;
        if (existing != null) {
          existing['local_operation_id'] = op['operation_id'];
          if (urgencies.indexOf(op['urgency'] as String) >
              urgencies.indexOf(existing['urgency'] as String)) {
            existing['urgency'] = op['urgency'];
          }
          if (existing['category'] == '') existing['category'] = op['category'];
        } else {
          items.add({
            'id': op['local_id'],
            'name': op['name'],
            'urgency': op['urgency'],
            'category': op['category'],
            'local_operation_id': op['operation_id'],
            'list_id': id,
          });
        }
      } else if (op['kind'] == 'buy') {
        final additionKey =
            (document['addition_keys'] as Map?)?[op['add_operation_id']];
        final item = items.where((item) {
          if (op['add_operation_id'] != null) {
            return item['local_operation_id'] == op['add_operation_id'] ||
                item['item_key'] != null && item['item_key'] == additionKey;
          }
          return item['item_key'] == op['item_key'];
        }).firstOrNull;
        if (item != null) {
          items.remove(item);
          final boughtAt = DateTime.parse(op['occurred_at'] as String);
          final days = op['return_in_days'] as int?;
          purchases.insert(0, {
            ...item,
            'id': null,
            'pending': true,
            'bought_at': op['occurred_at'],
            'bought_by_name': memberName,
            'return_at': days == null
                ? null
                : boughtAt.add(Duration(days: days)).toIso8601String(),
          });
        }
      }
    }
    return data;
  }

  Future<void> synchronize() {
    if (_sync != null) return _sync!;
    final work = _synchronize();
    _sync = work;
    return work.whenComplete(() => _sync = null);
  }

  Future<void> _synchronize() async {
    if (!ready || !current()) return;
    syncing = true;
    error = null;
    changed();
    try {
      // Revalidate account/family before sending queued private data.
      final account = await api.accountState();
      if (!current()) return;
      if (account['family_id'] != familyId ||
          account['member']?['id'] != memberId) {
        throw ApiException(
          403,
          'Выбранная семья изменилась. Выберите семью заново.',
        );
      }
      offline = false;
      while (current() && operations.isNotEmpty) {
        final op = copyShoppingData(operations.first);
        if (op['blocked_error'] != null) break;
        Map<String, dynamic> result;
        try {
          result = await api.syncShopping(op..remove('blocked_error'));
        } on ApiException catch (exception) {
          if (exception.statusCode >= 500) rethrow;
          await _edit((data) {
            final row = (data['operations'] as List)
                .cast<Map<String, dynamic>>()
                .firstWhere((row) => row['operation_id'] == op['operation_id']);
            row['blocked_error'] = exception.message;
          });
          break;
        }
        if (!current()) return;
        // Persist the receipt and refresh the base together. Until that succeeds
        // the operation stays queued and is safe to retry after a lost response.
        final fresh = await api.shoppingSnapshot();
        if (!current()) return;
        await _edit((data) {
          data['lists'] = fresh['lists'];
          data['snapshots'] = fresh['snapshots'];
          (data['operations'] as List).removeWhere(
            (row) => row['operation_id'] == op['operation_id'],
          );
          if (op['kind'] == 'add') {
            (data['addition_keys'] ??=
                    <String, dynamic>{})[op['operation_id']] =
                result['item_key'];
          }
          if (op['kind'] == 'resolve') {
            (data['conflicts'] as List).removeWhere(
              (row) => row['operation_id'] == op['conflict_operation_id'],
            );
          }
          if (result['status'] == 'conflict') {
            (data['conflicts'] as List).add({
              ...result,
              'operation_id': op['operation_id'],
            });
          } else if (result['status'] == 'already_bought') {
            (data['notices'] as List).add(
              '${result['name']}: покупка уже была отмечена.',
            );
            if ((data['notices'] as List).length > 20) {
              (data['notices'] as List).removeAt(0);
            }
          }
          final dependencies = (data['operations'] as List)
              .map((row) => row['add_operation_id'])
              .toSet();
          (data['addition_keys'] as Map?)?.removeWhere(
            (id, _) => !dependencies.contains(id),
          );
          data['last_sync'] = DateTime.now().toUtc().toIso8601String();
        });
      }
      final fresh = await api.shoppingSnapshot();
      if (!current()) return;
      await _edit((data) {
        data['lists'] = fresh['lists'];
        data['snapshots'] = fresh['snapshots'];
        data['last_sync'] = DateTime.now().toUtc().toIso8601String();
      });
    } on UnauthorizedException {
      // AuthStore handles rejected sessions. Never discard the owner's queue.
    } on ApiException catch (exception) {
      if (exception.statusCode >= 500) offline = true;
      error = exception.message;
    } on ServerUnavailableException {
      offline = true;
    } catch (_) {
      offline = true;
      error = 'Синхронизация не завершена. Изменения сохранены на устройстве.';
    } finally {
      syncing = false;
      if (current()) changed();
    }
  }

  Future<void> dismissNotice(String notice) =>
      _edit((data) => (data['notices'] as List).remove(notice));

  Future<void> discardBlocked(String operationId) => _edit((data) {
    // Dependent purchases cannot survive discarding their offline addition.
    (data['operations'] as List).removeWhere(
      (op) =>
          op['operation_id'] == operationId ||
          op['add_operation_id'] == operationId,
    );
  });
}

/// Background replay never writes the foreground document, preventing lost
/// edits when Android runs a worker while the user is changing the list.
Future<bool> replayShoppingInBackground({
  required ApiClient api,
  required LocalStorage storage,
  required String key,
  required int familyId,
  required int memberId,
  required Future<bool> Function() current,
}) async {
  try {
    if (!await current()) return true;
    final saved = await storage.read(key);
    if (saved == null) return true;
    final data = jsonDecode(saved) as Map<String, dynamic>;
    final operations = (data['operations'] as List)
        .cast<Map<String, dynamic>>();
    if (operations.isEmpty) return true;
    final account = await api.accountState();
    if (!await current() ||
        account['family_id'] != familyId ||
        account['member']?['id'] != memberId) {
      return true;
    }
    for (final operation in operations) {
      if (!await current()) return true;
      if (operation['blocked_error'] != null) return true;
      await api.syncShopping(operation);
    }
    return true;
  } on UnauthorizedException {
    return true;
  } on ApiException catch (exception) {
    return exception.statusCode < 500;
  } catch (_) {
    return false;
  }
}

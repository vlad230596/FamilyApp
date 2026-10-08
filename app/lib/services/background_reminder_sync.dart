import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/config.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'package:familyapp/state/auth_store.dart';

final backgroundReminderSyncProvider = Provider(
  (ref) => BackgroundReminderSync(),
);
const _workName = 'familyapp-reminder-sync';
const _contextKey = 'reminder_sync_context';

@pragma('vm:entry-point')
void reminderSyncDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    if (task != _workName) return true;
    const storage = FlutterSecureStorage();
    final tokenStorage = TokenStorage();
    final notifications = ChoreNotifications();
    return refreshBackgroundReminders(
      api: ApiClient(apiBaseUrl),
      notifications: notifications,
      readToken: tokenStorage.read,
      readContext: () => storage.read(key: _contextKey),
    );
  });
}

/// Kept separate from platform registration so revoked/failing syncs can be tested.
Future<bool> refreshBackgroundReminders({
  required ApiClient api,
  required ChoreNotifications notifications,
  required Future<String?> Function() readToken,
  required Future<String?> Function() readContext,
}) async {
  final context = await readContext();
  final token = await readToken();
  if (context == null || token == null) return true;
  bool unauthorized = false;
  Future<bool> current() async =>
      await readContext() == context && await readToken() == token;
  try {
    final owner = jsonDecode(context) as Map<String, dynamic>;
    api.token = token;
    final account = await api.accountState().timeout(
      const Duration(seconds: 20),
    );
    if (!await current()) return true;
    if (account['family_id'] != owner['family_id'] ||
        account['member']?['id'] != owner['member_id']) {
      await notifications.clearIfCurrent(current);
      return true;
    }
    final chores = await api.listChores().timeout(const Duration(seconds: 20));
    final reminders = await api.choreReminders().timeout(
      const Duration(seconds: 20),
    );
    if (!await current()) return true;
    // No authentication token is included in a notification payload or work input.
    if (reminders.any(
      (r) =>
          r['family_id'] != owner['family_id'] ||
          r['member_id'] != owner['member_id'],
    )) {
      return false;
    }
    await notifications.synchronizeGuarded(
      reminders,
      current: current,
      retained: {
        for (final chore in chores)
          if (chore.active &&
              chore.responsibleMemberId == owner['member_id'] &&
              chore.dueDate != null &&
              chore.dueAnswer == null)
            notificationTag({
              'chore_id': chore.id,
              'occurrence_date': chore.dueDate,
              'revision': chore.revision,
              'member_id': owner['member_id'],
            }),
      },
    );
    return true;
  } on UnauthorizedException {
    unauthorized = true;
  } catch (_) {
    // Preserve the last usable alarms when offline; WorkManager retries later.
    return false;
  }
  if (unauthorized && await current()) {
    await notifications.clearIfCurrent(current);
  }
  return true;
}

class BackgroundReminderSync {
  final _storage = const FlutterSecureStorage();
  Future<void> _queue = Future.value();
  Future<void>? _initialization;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> configure(int memberId, int familyId) => _enqueue(() async {
    if (!supported) return;
    _initialization ??= Workmanager().initialize(reminderSyncDispatcher);
    await _initialization;
    await _storage.write(
      key: _contextKey,
      value: jsonEncode({
        'member_id': memberId,
        'family_id': familyId,
        'generation': DateTime.now().microsecondsSinceEpoch,
      }),
    );
    await Workmanager().registerPeriodicTask(
      _workName,
      _workName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  });

  Future<void> clear() => _enqueue(() async {
    if (!supported) return;
    // Invalidate an in-flight worker before cancelling its native work/alarms.
    await _storage.delete(key: _contextKey);
    await Workmanager().cancelByUniqueName(_workName);
  });
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }
}

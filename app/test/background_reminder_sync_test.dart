import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/services/background_reminder_sync.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'widget_test.dart' show FakeApiClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const token = 'test-token';
  final owner = jsonEncode({'member_id': 1, 'family_id': 1, 'generation': 1});

  test(
    'background sync schedules only the authenticated selected family',
    () async {
      final api = BackgroundApi();
      final notifications = BackgroundNotifications();
      expect(
        await refreshBackgroundReminders(
          api: api,
          notifications: notifications,
          readToken: () async => token,
          readContext: () async => owner,
        ),
        isTrue,
      );
      expect(api.token, token);
      expect(notifications.scheduled.single['family_id'], 1);
    },
  );

  test(
    'sign-out or a new foreground generation discards an in-flight response',
    () async {
      String? context = owner;
      final api = BackgroundApi()..afterFetch = () => context = null;
      final notifications = BackgroundNotifications();
      expect(
        await refreshBackgroundReminders(
          api: api,
          notifications: notifications,
          readToken: () async => token,
          readContext: () async => context,
        ),
        isTrue,
      );
      expect(notifications.scheduled, isEmpty);
      expect(notifications.cleared, 0);
    },
  );

  test('offline preserves usable notifications and requests retry', () async {
    final api = BackgroundApi()..offline = true;
    final notifications = BackgroundNotifications();
    expect(
      await refreshBackgroundReminders(
        api: api,
        notifications: notifications,
        readToken: () async => token,
        readContext: () async => owner,
      ),
      isFalse,
    );
    expect(notifications.cleared, 0);
  });

  test(
    'revoked token cancels notifications without deleting another session',
    () async {
      final api = BackgroundApi()..revoked = true;
      final notifications = BackgroundNotifications();
      expect(
        await refreshBackgroundReminders(
          api: api,
          notifications: notifications,
          readToken: () async => token,
          readContext: () async => owner,
        ),
        isTrue,
      );
      expect(notifications.cleared, 1);
    },
  );

  test(
    'a changed server family cannot schedule another familys reminders',
    () async {
      final notifications = BackgroundNotifications();
      final wrongOwner = jsonEncode({'member_id': 2, 'family_id': 2});
      expect(
        await refreshBackgroundReminders(
          api: BackgroundApi(),
          notifications: notifications,
          readToken: () async => token,
          readContext: () async => wrongOwner,
        ),
        isTrue,
      );
      expect(notifications.scheduled, isEmpty);
      expect(notifications.cleared, 1);
    },
  );
}

class BackgroundApi extends FakeApiClient {
  void Function()? afterFetch;
  bool offline = false, revoked = false;
  @override
  Future<Map<String, dynamic>> accountState() async {
    if (revoked) throw UnauthorizedException('Revoked');
    if (offline) throw Exception('Offline');
    return account;
  }

  @override
  Future<List<Map<String, dynamic>>> choreReminders() async {
    afterFetch?.call();
    return [
      {'kind': 'duty', 'chore_id': 1, 'member_id': 1, 'family_id': 1},
    ];
  }
}

class BackgroundNotifications extends ChoreNotifications {
  List<Map<String, dynamic>> scheduled = [];
  int cleared = 0;
  @override
  Future<void> synchronizeGuarded(
    List<Map<String, dynamic>> reminders, {
    required Future<bool> Function() current,
    Set<String> retained = const {},
  }) async {
    if (await current()) scheduled = reminders;
  }

  @override
  Future<void> clearIfCurrent(Future<bool> Function() current) async {
    if (await current()) cleared++;
  }
}

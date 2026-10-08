import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:familyapp/services/chore_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var enabled = true;
  var exact = true;
  var active = <Map<String, dynamic>>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    enabled = true;
    exact = true;
    active = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'getNotificationAppLaunchDetails':
              return {'notificationLaunchedApp': false};
            case 'areNotificationsEnabled':
              return enabled;
            case 'canScheduleExactNotifications':
              return exact;
            case 'getActiveNotifications':
              return active;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<String, dynamic> reminder() => {
    'chore_id': 7,
    'occurrence_date': '2099-10-07',
    'scheduled_at': '2099-10-07T23:00:00+03:00',
    'timezone': 'Europe/Moscow',
    'revision': 2,
    'member_id': 4,
    'family_id': 3,
    'title': 'Посудомойка запущена?',
  };

  test('duty reminders open the app and do not offer check answers', () async {
    await ChoreNotifications().synchronize([
      {...reminder(), 'kind': 'duty'},
    ]);
    final args =
        calls.singleWhere((call) => call.method == 'zonedSchedule').arguments
            as Map;
    final specifics = args['platformSpecifics'] as Map;
    final actions = specifics['actions'] as List;
    expect(actions.length, 1);
    expect((actions.single as Map)['id'], 'open');
    expect(
      notificationTag({...reminder(), 'kind': 'duty'}),
      isNot(notificationTag(reminder())),
    );
  });

  test(
    'revocation during scheduling cancels the just-created stale alert',
    () async {
      var checks = 0;
      await ChoreNotifications().synchronizeGuarded([
        reminder(),
        {...reminder(), 'chore_id': 8},
      ], current: () async => ++checks < 3);
      expect(calls.where((call) => call.method == 'zonedSchedule').length, 1);
      expect(calls.last.method, 'cancel');
    },
  );

  test(
    'schedules private Android reminders with authenticated Yes/No actions',
    () async {
      await ChoreNotifications().synchronize([reminder()]);
      final scheduled =
          calls.singleWhere((call) => call.method == 'zonedSchedule').arguments
              as Map;
      expect(jsonDecode(scheduled['payload'] as String)['member_id'], 4);
      expect(scheduled['timeZoneName'], 'Europe/Moscow');
      final specifics = scheduled['platformSpecifics'] as Map;
      expect(
        specifics['scheduleMode'],
        AndroidScheduleMode.exactAllowWhileIdle.name,
      );
      expect(specifics['visibility'], NotificationVisibility.private.index);
      expect((specifics['actions'] as List).map((action) => action['id']), [
        'yes',
        'no',
      ]);
      expect(
        (specifics['actions'] as List).every(
          (action) => action['showsUserInterface'] == true,
        ),
        isTrue,
      );
    },
  );

  test(
    'keeps unanswered visible alert and cancels stale alerts on sync',
    () async {
      final tag = notificationTag(reminder());
      active = [
        {'id': 17, 'tag': tag},
        {'id': 18, 'tag': 'obsolete'},
      ];
      await ChoreNotifications().synchronize([], retained: {tag});
      expect(calls.where((call) => call.method == 'cancelAll'), isEmpty);
      final cancellations = calls
          .where((call) => call.method == 'cancel')
          .toList();
      expect(cancellations.length, 1);
      expect((cancellations.single.arguments as Map)['id'], 18);
    },
  );

  test(
    'denied permission prevents scheduling and exact denial uses fallback',
    () async {
      final notifications = ChoreNotifications();
      enabled = false;
      await notifications.synchronize([reminder()]);
      expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
      enabled = true;
      exact = false;
      await notifications.synchronize([reminder()]);
      final scheduled =
          calls.singleWhere((call) => call.method == 'zonedSchedule').arguments
              as Map;
      expect(
        (scheduled['platformSpecifics'] as Map)['scheduleMode'],
        AndroidScheduleMode.inexactAllowWhileIdle.name,
      );
    },
  );

  test('sign-out clear runs after pending scheduling', () async {
    final notifications = ChoreNotifications();
    await Future.wait([
      notifications.synchronize([reminder()]),
      notifications.clear(),
    ]);
    expect(calls.last.method, 'cancelAll');
  });
}

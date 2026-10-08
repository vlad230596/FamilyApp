import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final choreNotificationsProvider = Provider((ref) => ChoreNotifications());

/// Android reminders are local. Actions open the app to authenticate the answer.
class ChoreNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> _queue = Future.value();
  NotificationResponse? _pendingResponse;
  void Function(NotificationResponse)? onResponse;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (onResponse != null) {
          onResponse!(response);
        } else {
          _pendingResponse = response;
        }
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _pendingResponse = launch!.notificationResponse;
    }
  }

  NotificationResponse? takePendingResponse() {
    final response = _pendingResponse;
    _pendingResponse = null;
    return response;
  }

  Future<String> deviceTimezone() async => supported
      ? (await FlutterTimezone.getLocalTimezone()).identifier
      : DateTime.now().timeZoneOffset == const Duration(hours: 3)
      ? 'Europe/Moscow'
      : 'Etc/UTC';

  Future<bool> requestPermission() async {
    await initialize();
    if (!supported) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    final allowed = await android.requestNotificationsPermission() ?? false;
    if (allowed) await android.requestExactAlarmsPermission();
    return allowed;
  }

  // Serialize cancellation and scheduling so sign-out always cancels old alarms.
  Future<void> synchronize(
    List<Map<String, dynamic>> reminders, {
    Set<String> retained = const {},
  }) => _synchronize(reminders, retained: retained);

  Future<void> synchronizeGuarded(
    List<Map<String, dynamic>> reminders, {
    required Future<bool> Function() current,
    Set<String> retained = const {},
  }) => _synchronize(reminders, retained: retained, current: current);

  Future<void> _synchronize(
    List<Map<String, dynamic>> reminders, {
    Set<String> retained = const {},
    Future<bool> Function()? current,
  }) => _enqueue(() async {
    await initialize();
    if (!supported) return;
    if (current != null && !await current()) return;
    await _plugin.cancelAllPendingNotifications();
    for (final active in await _plugin.getActiveNotifications()) {
      if (current != null && !await current()) return;
      if (!retained.contains(active.tag)) {
        await _plugin.cancel(id: active.id!, tag: active.tag);
      }
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    if (await android.areNotificationsEnabled() != true) return;
    final exact = await android.canScheduleExactNotifications() ?? false;
    for (final reminder in reminders) {
      if (current != null && !await current()) return;
      final when = tz.TZDateTime.from(
        DateTime.parse(reminder['scheduled_at'] as String),
        tz.getLocation(reminder['timezone'] as String),
      );
      if (!when.isAfter(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        id: notificationId(notificationTag(reminder)),
        title: reminder['title'] as String,
        body: reminder['kind'] == 'duty'
            ? 'Пора выполнить дежурство. Откройте приложение.'
            : 'Пора проверить. Выберите «Да» или «Нет».',
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'regular_tasks',
            'Регулярные задачи',
            channelDescription: 'Напоминания о назначенных вам проверках',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
            tag: notificationTag(reminder),
            actions: reminder['kind'] == 'duty'
                ? const [
                    AndroidNotificationAction(
                      'open',
                      'Открыть',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                  ]
                : const [
                    AndroidNotificationAction(
                      'yes',
                      'Да',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                    AndroidNotificationAction(
                      'no',
                      'Нет',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                  ],
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode(reminder),
      );
      if (current != null && !await current()) {
        await _plugin.cancel(
          id: notificationId(notificationTag(reminder)),
          tag: notificationTag(reminder),
        );
        return;
      }
    }
  });

  Future<void> clear() => _enqueue(() async {
    await initialize();
    if (supported) await _plugin.cancelAll();
  });

  Future<void> clearIfCurrent(Future<bool> Function() current) =>
      _enqueue(() async {
        await initialize();
        if (supported && await current()) await _plugin.cancelAll();
      });

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }
}

String notificationTag(Map<String, dynamic> data) =>
    '${data['kind'] == 'duty' ? 'duty|' : ''}${data['chore_id']}|${data['occurrence_date']}|${data['revision']}|${data['member_id']}';

int notificationId(String tag) {
  var hash = 2166136261;
  for (final unit in tag.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
  }
  return hash;
}

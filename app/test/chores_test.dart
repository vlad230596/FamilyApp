import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:familyapp/main.dart';
import 'package:familyapp/models/chore.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/chore_store.dart';
import 'package:familyapp/state/family_store.dart';

import 'widget_test.dart' show FakeApiClient, MemoryTokenStorage, fakeMember;

void main() {
  Future<void> openTasks(
    WidgetTester tester,
    ChoreApi api, {
    Size size = const Size(390, 844),
    RecordingNotifications? notifications,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage('token')),
          if (notifications != null)
            choreNotificationsProvider.overrideWithValue(notifications),
        ],
        child: const FamilyApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Задачи'));
    await tester.pumpAndSettle();
  }

  testWidgets('assignee answers No and it remains distinct from no answer', (
    tester,
  ) async {
    final api = ChoreApi();
    await openTasks(tester, api);
    expect(find.text('Нет'), findsOneWidget);
    await tester.ensureVisible(find.text('Нет'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Нет'));
    await tester.pumpAndSettle();
    expect(api.answered, isFalse);
    expect(find.text('Проверка 07.10.2026: Нет'), findsOneWidget);
    expect(find.text('Да'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent can edit another members task but cannot answer it', (
    tester,
  ) async {
    await openTasks(tester, ChoreApi(responsibleId: 2));
    expect(find.text('Изменить'), findsOneWidget);
    expect(find.text('Да'), findsNothing);
    expect(find.text('Нет'), findsNothing);
  });

  testWidgets('child answers assigned task without management actions', (
    tester,
  ) async {
    await openTasks(tester, ChoreApi(member: fakeMember(role: 'child')));
    expect(find.text('Да'), findsOneWidget);
    expect(find.text('Изменить'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  for (final size in [const Size(320, 640), const Size(1200, 900)]) {
    testWidgets('task form fits ${size.width} wide screen and saves schedule', (
      tester,
    ) async {
      final api = ChoreApi();
      await openTasks(tester, api, size: size);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Что проверять'),
        'Геля для стирки достаточно?',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Интервал в днях'),
        '7',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.saved?['interval_days'], 7);
      expect(api.saved?['responsible_member_id'], 1);
      expect(api.saved?['reminder_time'], '23:00');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('history shows who answered and original title', (tester) async {
    await openTasks(tester, ChoreApi());
    await tester.ensureVisible(find.text('История'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(find.text('07.10.2026 — Нет'), findsOneWidget);
    expect(find.textContaining('Мама ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restore preserves alerts and sign-out blocks an in-flight reminder sync',
    (tester) async {
      final api = ChoreApi();
      final notifications = RecordingNotifications();
      await openTasks(tester, api, notifications: notifications);
      expect(notifications.cleared, 0);
      final before = notifications.synced;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FamilyApp)),
      );
      api.reminderGate = Completer<List<Map<String, dynamic>>>();
      final refresh = container.read(choreStoreProvider.notifier).refresh();
      await tester.pump();
      notifications.clearGate = Completer<void>();
      final logout = container.read(authStoreProvider.notifier).logout();
      await tester.pump();
      expect(container.read(authStoreProvider).status, AuthStatus.signedOut);
      api.reminderGate!.complete([]);
      await refresh;
      expect(notifications.synced, before);
      notifications.clearGate!.complete();
      await logout;
      await tester.pumpAndSettle();
      expect(notifications.cleared, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'notification identities are stable and include assignee and revision',
    () {
      final data = {
        'chore_id': 1,
        'occurrence_date': '2026-10-07',
        'revision': 1,
        'member_id': 2,
      };
      final tag = notificationTag(data);
      expect(notificationId(tag), notificationId(notificationTag({...data})));
      expect(notificationId(tag), isNonNegative);
      expect(
        notificationId(notificationTag({...data, 'member_id': 3})),
        isNot(notificationId(tag)),
      );
      expect(
        notificationId(notificationTag({...data, 'revision': 2})),
        isNot(notificationId(tag)),
      );
    },
  );
}

class RecordingNotifications extends ChoreNotifications {
  int synced = 0;
  int cleared = 0;
  Completer<void>? clearGate;

  @override
  Future<void> synchronize(
    List<Map<String, dynamic>> reminders, {
    Set<String> retained = const {},
  }) async {
    synced++;
  }

  @override
  Future<void> clear() async {
    cleared++;
    if (clearGate != null) await clearGate!.future;
  }
}

class ChoreApi extends FakeApiClient {
  ChoreApi({this.responsibleId = 1, super.member});
  final int responsibleId;
  bool? answered;
  Map<String, dynamic>? saved;
  Completer<List<Map<String, dynamic>>>? reminderGate;

  @override
  Future<void> logout() async {}

  @override
  Future<List<Map<String, dynamic>>> choreReminders() async =>
      reminderGate == null ? [] : await reminderGate!.future;

  @override
  Future<List<Chore>> listChores() async => [
    Chore.fromJson({
      'id': 5,
      'title': 'Посудомойка запущена?',
      'responsible_member_id': responsibleId,
      'responsible_name': responsibleId == 1 ? 'Мама' : 'Папа',
      'start_date': '2026-10-07',
      'interval_days': 1,
      'weekdays': [],
      'reminder_time': '23:00',
      'timezone': 'Europe/Moscow',
      'active': true,
      'revision': 1,
      'due_date': '2026-10-07',
      'due_answer': answered,
      'next_at': '2026-10-08T23:00:00+03:00',
    }),
  ];

  @override
  Future<void> answerChore(
    int id,
    String date,
    bool answer,
    int revision,
  ) async {
    expect(id, 5);
    expect(date, '2026-10-07');
    expect(revision, 1);
    answered = answer;
  }

  @override
  Future<void> saveChore(Map<String, dynamic> data, {int? id}) async =>
      saved = data;

  @override
  Future<List<Map<String, dynamic>>> choreHistory(int id) async => [
    {
      'occurrence_date': '2026-10-07',
      'answer': false,
      'actor_name': 'Мама',
      'title': 'Посудомойка запущена?',
      'created_at': '2026-10-07T20:05:00+00:00',
    },
  ];
}

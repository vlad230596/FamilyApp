import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/main.dart';
import 'package:familyapp/screens/calendar_page.dart';
import 'package:familyapp/utils/dates.dart';
import 'package:familyapp/models/child.dart';
import 'package:familyapp/models/chore.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/models/restriction.dart';
import 'package:familyapp/models/restriction_type.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/services/background_reminder_sync.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeApiClient api,
    String? savedToken,
  }) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          backgroundReminderSyncProvider.overrideWithValue(NoBackgroundSync()),
          tokenStorageProvider.overrideWithValue(
            MemoryTokenStorage(savedToken),
          ),
        ],
        child: const FamilyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('registration offers a separate account', (tester) async {
    await pumpApp(tester, api: FakeApiClient());
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pumpAndSettle();
    expect(find.text('Регистрация'), findsOneWidget);
    expect(find.text('Создать аккаунт'), findsOneWidget);
  });

  testWidgets('account without membership offers create or join', (
    tester,
  ) async {
    await pumpApp(
      tester,
      api: FakeApiClient(withFamily: false),
      savedToken: 'saved-token',
    );
    expect(find.text('Создать семью'), findsOneWidget);
    expect(find.text('Присоединиться'), findsOneWidget);
    expect(find.text('Календарь'), findsNothing);
  });

  testWidgets('registers then creates a family', (tester) async {
    await pumpApp(tester, api: FakeApiClient());
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Мама');
    await tester.enterText(fields.at(1), 'mama');
    await tester.enterText(fields.at(2), 'secret-123');
    await tester.enterText(fields.at(3), 'secret-123');
    await tester.tap(find.text('Создать аккаунт'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Семья');
    await tester.tap(find.text('Создать семью'));
    await tester.pumpAndSettle();
    expect(find.text('Календарь'), findsWidgets);
  });

  testWidgets('accepts an invitation after separate login', (tester) async {
    await pumpApp(
      tester,
      api: FakeApiClient(withFamily: false),
      savedToken: 'saved-token',
    );
    await tester.enterText(find.byType(TextFormField).last, 'invitation-code');
    await tester.tap(find.text('Присоединиться'));
    await tester.pumpAndSettle();
    expect(find.text('Календарь'), findsWidgets);
  });

  testWidgets('family selection fits small screens and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(375, 667), const Size(667, 375)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              FakeApiClient(withFamily: false),
            ),
            backgroundReminderSyncProvider.overrideWithValue(
              NoBackgroundSync(),
            ),
            tokenStorageProvider.overrideWithValue(
              MemoryTokenStorage('saved-token'),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const AuthGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Создать семью'), findsOneWidget);
    }
  });

  testWidgets(
    'daily shell keeps navigation usable across widths and large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      for (final size in [
        const Size(375, 667),
        const Size(667, 375),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(FakeApiClient()),
              backgroundReminderSyncProvider.overrideWithValue(
                NoBackgroundSync(),
              ),
              tokenStorageProvider.overrideWithValue(
                MemoryTokenStorage('saved-token'),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const AuthGate(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Дела'), findsOneWidget);
        await tester.tap(find.text('Дела').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Покупки').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'daily progress counts answered checks and confirmed duties, excluding drafts',
    (tester) async {
      await pumpApp(tester, api: DailyApiClient(), savedToken: 'saved-token');
      expect(find.text('2 из 4 дел завершено'), findsOneWidget);
      expect(find.text('Ждут подтверждения'), findsOneWidget);
      expect(find.text('Рассмотреть'), findsOneWidget);
      expect(find.text('Снова можно'), findsNothing);
    },
  );

  testWidgets(
    'calendar month and selected day survive compact to desktop resize',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await pumpApp(tester, api: FakeApiClient(), savedToken: 'saved-token');
      await tester.tap(find.text('Календарь').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Следующий месяц'));
      await tester.pumpAndSettle();
      var grid = tester.widget<MonthGrid>(find.byType(MonthGrid));
      final expectedMonth = grid.month;
      await tester.tap(
        find.descendant(of: find.byType(MonthGrid), matching: find.text('15')),
      );
      await tester.pumpAndSettle();
      final expectedDate = DateTime(
        expectedMonth.year,
        expectedMonth.month,
        15,
      );
      expect(
        sameDay(
          tester.widget<MonthGrid>(find.byType(MonthGrid)).selectedDate,
          expectedDate,
        ),
        isTrue,
      );
      for (final size in [const Size(1440, 900), const Size(375, 800)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        grid = tester.widget<MonthGrid>(find.byType(MonthGrid));
        expect(grid.month, expectedMonth);
        expect(sameDay(grid.selectedDate, expectedDate), isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('shows login without a saved session', (tester) async {
    await pumpApp(tester, api: FakeApiClient());

    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('logs in and shows today-first navigation', (tester) async {
    await pumpApp(tester, api: FakeApiClient());

    await tester.enterText(find.byType(TextField).at(0), 'mama');
    await tester.enterText(find.byType(TextField).at(1), 'secret-123');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();

    expect(find.text('Календарь'), findsWidgets);
    expect(find.text('Сегодня'), findsWidgets);
    expect(find.text('Дела'), findsOneWidget);
    expect(find.text('Семья'), findsOneWidget);
    expect(find.text('Сегодня ограничений нет'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('Календарь').last);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('restores saved session for a child without admin actions', (
    tester,
  ) async {
    await pumpApp(
      tester,
      api: FakeApiClient(member: fakeMember(role: 'child')),
      savedToken: 'saved-token',
    );

    expect(find.text('Календарь'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}

Member fakeMember({String role = 'parent'}) => Member(
  id: 1,
  name: 'Мама',
  icon: 'star',
  role: role,
  login: 'mama',
  hasAccount: true,
);

class MemoryTokenStorage extends TokenStorage {
  MemoryTokenStorage(this._token);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> delete() async => _token = null;
}

class NoBackgroundSync extends BackgroundReminderSync {
  @override
  Future<void> configure(int memberId, int familyId) async {}
  @override
  Future<void> clear() async {}
}

class FakeApiClient extends ApiClient {
  FakeApiClient({this.withFamily = true, Member? member})
    : member = member ?? fakeMember(),
      super('http://127.0.0.1:5055');

  final bool withFamily;
  final Member member;

  Map<String, dynamic> get account => {
    'user': {'id': 1, 'name': 'Мама', 'login': 'mama'},
    'families': withFamily
        ? [
            {'id': 1, 'name': 'Семья', 'role': member.role},
          ]
        : [],
    'member': withFamily
        ? {
            'id': member.id,
            'name': member.name,
            'icon': member.icon,
            'role': member.role,
            'login': member.login,
            'has_account': member.hasAccount,
          }
        : null,
    'family_id': withFamily ? 1 : null,
  };

  @override
  Future<AuthResult> login(String login, String password) async =>
      AuthResult('token', withFamily ? member : null)..account = account;

  @override
  Future<AuthResult> register(
    String name,
    String login,
    String password,
  ) async => AuthResult('token', null)
    ..account = {...account, 'member': null, 'families': [], 'family_id': null};

  Map<String, dynamic> get joinedAccount =>
      FakeApiClient(member: member).account;

  @override
  Future<Map<String, dynamic>> createFamily(String name) async => joinedAccount;

  @override
  Future<Map<String, dynamic>> acceptInvitation(String code) async =>
      joinedAccount;

  @override
  Future<Map<String, dynamic>> accountState() async => account;

  @override
  Future<Map<String, dynamic>> duties() async => {
    'occurrences': [],
    'duties': [],
    'statistics': [],
    'away_periods': [],
  };

  @override
  Future<Map<String, dynamic>> shopping() async => {
    'lists': [],
    'items': [],
    'purchases': [],
  };

  @override
  Future<List<Member>> listMembers() async => [member];

  @override
  Future<List<Child>> listChildren() async => [];

  @override
  Future<List<Chore>> listChores() async => [];

  @override
  Future<List<Map<String, dynamic>>> choreReminders() async => [];

  @override
  Future<List<RestrictionType>> listRestrictionTypes() async => [];

  @override
  Future<List<Restriction>> listRestrictions() async => [];

  @override
  Future<List<Restriction>> listRestrictionsForRange(
    DateTime start,
    DateTime end,
  ) async => [];
}

class DailyApiClient extends FakeApiClient {
  @override
  Future<Map<String, dynamic>> duties() async => {
    'occurrences': [
      for (final status in ['confirmed', 'pending', 'open'])
        {
          'id': status.hashCode,
          'title': 'Дежурство $status',
          'status': status,
          'occurrence_date': DateTime.now().toIso8601String().substring(0, 10),
          'assigned_name': 'Мама',
          'away': false,
        },
    ],
    'duties': [],
    'statistics': [],
    'away_periods': [],
  };
  @override
  Future<List<Chore>> listChores() async => [
    Chore.fromJson({
      'id': 10,
      'title': 'Проверка Нет',
      'responsible_member_id': 1,
      'responsible_name': 'Мама',
      'start_date': '2026-01-01',
      'interval_days': 1,
      'weekdays': [],
      'reminder_time': '18:00',
      'timezone': 'Europe/Moscow',
      'active': true,
      'revision': 1,
      'due_date': DateTime.now().toIso8601String().substring(0, 10),
      'due_answer': false,
      'next_at': null,
    }),
  ];
}

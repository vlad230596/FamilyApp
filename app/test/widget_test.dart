import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/main.dart';
import 'package:familyapp/models/child.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/models/restriction.dart';
import 'package:familyapp/models/restriction_type.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeApiClient api,
    String? savedToken,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
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

  testWidgets('shows login without a saved session', (tester) async {
    await pumpApp(tester, api: FakeApiClient());

    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('logs in and shows calendar-first navigation', (tester) async {
    await pumpApp(tester, api: FakeApiClient());

    await tester.enterText(find.byType(TextField).at(0), 'mama');
    await tester.enterText(find.byType(TextField).at(1), 'secret-123');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();

    expect(find.text('Календарь'), findsWidgets);
    expect(find.text('Ограничения'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.textContaining('Сегодня: 0 ограничений'), findsOneWidget);
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
  Future<List<Member>> listMembers() async => [member];

  @override
  Future<List<Child>> listChildren() async => [];

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

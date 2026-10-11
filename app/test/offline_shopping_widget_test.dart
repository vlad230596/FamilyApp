import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/main.dart';
import 'package:familyapp/screens/shopping_page.dart';
import 'package:familyapp/services/local_storage.dart';
import 'package:familyapp/services/shopping_sync.dart';
import 'package:familyapp/services/background_reminder_sync.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/state/household_store.dart';
import 'shopping_sync_test.dart' show MemoryLocalStorage;
import 'widget_test.dart'
    show FakeApiClient, MemoryTokenStorage, NoBackgroundSync;

class OfflineApi extends FakeApiClient {
  bool rejected = false;
  @override
  Future<Map<String, dynamic>> accountState() async {
    if (rejected) {
      onUnauthorized?.call();
      throw UnauthorizedException('Сессия завершена.');
    }
    throw ServerUnavailableException();
  }
}

Future<MemoryLocalStorage> savedShopping(
  OfflineApi api, {
  String token = 'token',
}) async {
  final storage = MemoryLocalStorage();
  await storage.write(
    'offline_account_v1',
    jsonEncode({'session_token': token, 'account': api.account}),
  );
  await storage.write(
    shoppingStorageKey(1, 1, 1),
    jsonEncode({
      'lists': [
        {'id': 1, 'name': 'Продукты', 'is_main': 1},
      ],
      'snapshots': [
        {
          'list_id': 1,
          'items': [
            {
              'id': 1,
              'item_key': 'milk',
              'name': 'Молоко',
              'urgency': 'week',
              'category': '',
            },
          ],
          'purchases': [],
        },
      ],
      'operations': [],
      'conflicts': [],
      'notices': [],
      'last_sync': '2026-10-12T09:00:00Z',
    }),
  );
  return storage;
}

void main() {
  for (final size in [
    const Size(375, 667),
    const Size(667, 375),
    const Size(1200, 900),
  ]) {
    testWidgets(
      'offline launch, banner and purchase fit ${size.width} with large text',
      (tester) async {
        final api = OfflineApi();
        final storage = await savedShopping(api);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(api),
              tokenStorageProvider.overrideWithValue(
                MemoryTokenStorage('token'),
              ),
              localStorageProvider.overrideWithValue(storage),
              backgroundReminderSyncProvider.overrideWithValue(
                NoBackgroundSync(),
              ),
            ],
            child: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: const FamilyApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Покупки').last);
        await tester.pumpAndSettle();
        expect(
          find.text('Работаем локально. Нет связи с сервером.'),
          findsOneWidget,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FamilyApp)),
        );
        expect(container.read(authStoreProvider).status, AuthStatus.signedIn);
        expect(
          container.read(shoppingStoreProvider).rows('items').single['name'],
          'Молоко',
        );
        await tester.scrollUntilVisible(
          find.byTooltip('Куплено: Молоко'),
          160,
          scrollable: find
              .descendant(
                of: find.byType(ShoppingPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Куплено: Молоко'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Сохранить'));
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(container.read(shoppingStoreProvider).pending, 1);
        expect(container.read(shoppingStoreProvider).rows('items'), isEmpty);
        expect(
          container
              .read(shoppingStoreProvider)
              .rows('purchases')
              .single['pending'],
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'rejected cached session signs out and preserves only its owner queue',
    (tester) async {
      final api = OfflineApi()..rejected = true;
      final storage = await savedShopping(api);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            tokenStorageProvider.overrideWithValue(MemoryTokenStorage('token')),
            localStorageProvider.overrideWithValue(storage),
            backgroundReminderSyncProvider.overrideWithValue(
              NoBackgroundSync(),
            ),
          ],
          child: const FamilyApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Войти'), findsOneWidget);
      expect(await storage.read('offline_account_v1'), isNull);
      expect(await storage.read(shoppingStorageKey(1, 1, 1)), isNotNull);
    },
  );

  testWidgets(
    'a cached account from another session cannot unlock offline access',
    (tester) async {
      final api = OfflineApi();
      final storage = await savedShopping(api, token: 'another-token');
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            tokenStorageProvider.overrideWithValue(MemoryTokenStorage('token')),
            localStorageProvider.overrideWithValue(storage),
            backgroundReminderSyncProvider.overrideWithValue(
              NoBackgroundSync(),
            ),
          ],
          child: const FamilyApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Войти'), findsOneWidget);
      expect(find.text('Покупки'), findsNothing);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:familyapp/main.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/services/background_reminder_sync.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/utils/dates.dart';
import 'widget_test.dart'
    show FakeApiClient, MemoryTokenStorage, NoBackgroundSync, fakeMember;

void main() {
  Future<void> open(
    WidgetTester tester,
    HouseholdApi api,
    Size size, {
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage('token')),
          backgroundReminderSyncProvider.overrideWithValue(NoBackgroundSync()),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const FamilyApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('switch shopping lists and choose the Alice main list', (
    tester,
  ) async {
    final api = MultiListApi();
    await open(tester, api, const Size(320, 640));
    await tester.tap(find.text('Покупки').last);
    await tester.pumpAndSettle();
    expect(find.text('Главный семейный список'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дача').last);
    await tester.pumpAndSettle();
    expect(api.selected, 2);
    await tester.tap(find.text('Управление списками'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Сделать главным'));
    await tester.tap(find.text('Сделать главным'));
    await tester.pumpAndSettle();
    expect(api.main, 2);
    await tester.tap(find.text('Управление списками'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Новый список'));
    await tester.tap(find.text('Новый список'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Введите название'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Поездка',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(api.lists.last['name'], 'Поездка');
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(1200, 900),
    const Size(667, 375),
  ]) {
    testWidgets('shopping and duty forms work at ${size.width} width', (
      tester,
    ) async {
      final api = HouseholdApi();
      await open(tester, api, size);
      await tester.tap(find.text('Покупки').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Что купить'),
        'Хлеб',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.added?['name'], 'Хлеб');
      await tester.tap(find.text('Дела').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Дежурства'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Что нужно сделать'),
        'Убрать со стола',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.savedDuty?['title'], 'Убрать со стола');
      expect((api.savedDuty?['weekdays'] as List).length, 7);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('child can add shopping and submit own duty without management', (
    tester,
  ) async {
    final api = HouseholdApi(member: fakeMember(role: 'child'));
    await open(tester, api, const Size(375, 812));
    await tester.tap(find.text('Покупки').last);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.text('Дела').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дежурства'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Добавить период отсутствия'), findsNothing);
    await tester.tap(find.text('Выполнено').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Отметка будет отправлена родителю для подтверждения.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(api.completed?['performer_member_id'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shopping form keeps entered data after server error', (
    tester,
  ) async {
    final api = HouseholdApi()..failSave = true;
    await open(tester, api, const Size(375, 812));
    await tester.tap(find.text('Покупки').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Что купить'),
      'Хлеб',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Хлеб'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Нет связи'),
      ),
      findsOneWidget,
    );
  });

  for (final size in [const Size(375, 667), const Size(667, 375)]) {
    testWidgets('household screens fit large text at ${size.width} width', (
      tester,
    ) async {
      await open(tester, HouseholdApi(), size, scale: 2);
      await tester.tap(find.text('Дела').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Дежурства'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Покупки').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'purchase form schedules a return and history allows returning now',
    (tester) async {
      final api = HouseholdApi()
        ..items.add({
          'id': 1,
          'name': 'Молоко',
          'urgency': 'urgent',
          'category': 'Продукты',
        });
      await open(tester, api, const Size(375, 812));
      await tester.tap(find.text('Покупки').last);
      await tester.pumpAndSettle();
      expect(find.text('Продукты'), findsWidgets);
      await tester.tap(find.byTooltip('Куплено: Молоко'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Вернуть через, дней'),
        '7',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.boughtDays, 7);
      await tester.tap(find.text('Купленное'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Вернётся'), findsOneWidget);
      await tester.tap(find.text('Вернуть сейчас'));
      await tester.pumpAndSettle();
      expect(api.returnedId, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('parent reviews a child submission with a rating', (
    tester,
  ) async {
    final api = HouseholdApi()..pending = true;
    await open(tester, api, const Size(375, 812));
    await tester.tap(find.text('Дела').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дежурства'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рассмотреть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Нормально'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отлично').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(api.reviewed, {'approved': true, 'rating': 'great'});
    expect(tester.takeException(), isNull);
  });
}

class HouseholdApi extends FakeApiClient {
  HouseholdApi({super.member});
  Map<String, dynamic>? added, savedDuty, completed;
  Map<String, dynamic>? reviewed;
  final items = <Map<String, dynamic>>[];
  final purchases = <Map<String, dynamic>>[];
  int? boughtDays, returnedId;
  bool pending = false;
  bool failSave = false;
  @override
  Future<List<Member>> listMembers() async => [member];
  @override
  Future<Map<String, dynamic>> shopping() async => {
    'items': items,
    'purchases': purchases,
  };
  @override
  Future<Map<String, dynamic>> duties() async => {
    'duties': [],
    'statistics': [],
    'away_periods': [],
    'occurrences': [
      {
        'id': 1,
        'title': 'Помыть посуду',
        'occurrence_date': dateToIso(DateTime.now()),
        'assigned_name': member.name,
        'assigned_member_id': 1,
        'status': reviewed != null
            ? 'confirmed'
            : completed != null || pending
            ? 'pending'
            : 'open',
        'away': false,
      },
    ],
  };
  @override
  Future<void> addShopping(Map<String, dynamic> data) async {
    if (failSave) throw Exception('Нет связи');
    added = data;
    items.add({'id': 1, ...data});
  }

  @override
  Future<void> saveDuty(Map<String, dynamic> data, {int? id}) async =>
      savedDuty = data;
  @override
  Future<void> completeDuty(int id, Map<String, dynamic> data) async =>
      completed = data;

  @override
  Future<void> reviewDuty(int id, bool approved, String rating) async =>
      reviewed = {'approved': approved, 'rating': rating};
  @override
  Future<void> buyShopping(int id, int? days) async {
    boughtDays = days;
    final item = items.removeAt(0);
    purchases.add({
      ...item,
      'bought_at': DateTime.now().toIso8601String(),
      'bought_by_name': member.name,
      'return_at': days == null
          ? null
          : DateTime.now().add(Duration(days: days)).toIso8601String(),
    });
  }

  @override
  Future<void> returnShopping(int id, {bool cancel = false}) async {
    returnedId = id;
    purchases.first['returned_at'] = DateTime.now().toIso8601String();
  }
}

class MultiListApi extends HouseholdApi {
  int selected = 1, main = 1;
  final lists = <Map<String, dynamic>>[
    {'id': 1, 'name': '\u041f\u0440\u043e\u0434\u0443\u043a\u0442\u044b'},
    {'id': 2, 'name': '\u0414\u0430\u0447\u0430'},
  ];
  Map<String, dynamic> result() => {
    'list_id': selected,
    'lists': [
      for (final list in lists)
        {...list, 'is_main': list['id'] == main ? 1 : 0},
    ],
    'items': [],
    'purchases': [],
  };
  @override
  Future<Map<String, dynamic>> shopping() async {
    selected = main;
    return result();
  }

  @override
  Future<Map<String, dynamic>> shoppingList(int id) async {
    selected = id;
    return result();
  }

  @override
  Future<void> saveShoppingList(
    String name, {
    int? id,
    bool main = false,
  }) async {
    if (id == null) {
      lists.add({'id': lists.length + 1, 'name': name});
    } else {
      lists.firstWhere((list) => list['id'] == id)['name'] = name;
    }
    if (main) this.main = id!;
  }
}

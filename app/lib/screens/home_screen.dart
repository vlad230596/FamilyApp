import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/dialogs/restriction_dialog.dart';
import 'package:familyapp/dialogs/chore_dialog.dart';
import 'package:familyapp/screens/chores_page.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'package:familyapp/state/chore_store.dart';
import 'package:familyapp/screens/calendar_page.dart';
import 'package:familyapp/screens/restriction_history_page.dart';
import 'package:familyapp/screens/settings_page.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/state/household_store.dart';
import 'package:familyapp/screens/duties_page.dart';
import 'package:familyapp/screens/shopping_page.dart';
import 'package:familyapp/dialogs/duty_dialog.dart';
import 'package:familyapp/dialogs/household_action_dialog.dart';
import 'package:familyapp/screens/today_page.dart';
import 'package:familyapp/theme/solar_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  var _index = 0;
  var _duties = true;
  var _history = false;
  Timer? _timer;
  late final ChoreNotifications _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = ref.read(choreNotificationsProvider);
    ref.read(choreStoreProvider);
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    Future.microtask(() async {
      if (!mounted) return;
      final notifications = _notifications;
      try {
        await notifications.initialize();
        if (!mounted) return;
        notifications.onResponse = _notificationResponse;
        final response = notifications.takePendingResponse();
        if (response != null) await _notificationResponse(response);
      } catch (_) {
        // The task list remains available if Android initialization fails.
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _refresh();
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _notificationResponse(NotificationResponse response) async {
    if (!mounted) return;
    setState(() {
      _index = 1;
      _duties = false;
    });
    try {
      final data = jsonDecode(response.payload ?? '{}') as Map<String, dynamic>;
      if (data['kind'] == 'duty') {
        setState(() => _duties = true);
        ref.read(dutiesStoreProvider.notifier).refresh();
        return;
      }
    } catch (_) {
      // Malformed payloads open the task list without submitting an answer.
    }
    if (response.actionId != 'yes' && response.actionId != 'no') return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      final auth = ref.read(authStoreProvider);
      if (auth.member?.id != data['member_id'] ||
          auth.account?['family_id'] != data['family_id']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Напоминание относится к другому участнику или семье.',
            ),
          ),
        );
        return;
      }
      final store = ref.read(choreStoreProvider.notifier);
      // A sync may already be in progress when Android launches the app.
      for (
        var attempt = 0;
        attempt < 50 && ref.read(choreStoreProvider).busy;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
      }
      final saved = await store.answer(
        data['chore_id'] as int,
        data['occurrence_date'] as String,
        response.actionId == 'yes',
        data['revision'] as int,
      );
      if (mounted && saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ответ сохранён.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось обработать напоминание. Ответьте в списке задач.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _notifications.onResponse = null;
    super.dispose();
  }

  static const _destinations = [
    (Icons.wb_sunny_outlined, 'Сегодня'),
    (Icons.task_alt_outlined, 'Дела'),
    (Icons.calendar_month_outlined, 'Календарь'),
    (Icons.shopping_cart_outlined, 'Покупки'),
    (Icons.people_outline, 'Семья'),
  ];

  void _refresh() {
    ref.read(familyStoreProvider.notifier).refresh();
    ref.read(choreStoreProvider.notifier).refresh();
    ref.read(dutiesStoreProvider.notifier).refresh();
    ref.read(shoppingStoreProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(familyStoreProvider);
    final controller = ref.read(familyStoreProvider.notifier);
    final auth = ref.watch(authStoreProvider);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final pages = [
      TodayPage(onNavigate: (index) => setState(() => _index = index)),
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Дежурства'),
                  selected: _duties,
                  onSelected: (_) => setState(() => _duties = true),
                ),
                ChoiceChip(
                  label: const Text('Проверки'),
                  selected: !_duties,
                  onSelected: (_) => setState(() => _duties = false),
                ),
              ],
            ),
          ),
          Expanded(child: _duties ? const DutiesPage() : const ChoresPage()),
        ],
      ),
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Календарь'),
                  selected: !_history,
                  onSelected: (_) => setState(() => _history = false),
                ),
                ChoiceChip(
                  label: const Text('История'),
                  selected: _history,
                  onSelected: (_) => setState(() => _history = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: _history
                ? RestrictionHistoryPage(state: store, controller: controller)
                : CalendarPage(
                    state: store,
                    controller: controller,
                    showChildFilter: auth.isParent,
                  ),
          ),
        ],
      ),
      const ShoppingPage(),
      SettingsPage(state: store, controller: controller),
    ];
    final content = Column(
      children: [
        if (store.error != null)
          MaterialBanner(
            content: Text(store.error!),
            actions: [
              TextButton(
                onPressed: controller.clearError,
                child: const Text('Закрыть'),
              ),
            ],
          ),
        if (store.loading) const LinearProgressIndicator(),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: pages[_index],
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/branding/familyapp-icon-1024.png',
              semanticLabel: 'FamilyApp',
            ),
          ),
        ),
        title: Text(
          _destinations[_index].$2,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: store.loading ? null : _refresh,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              SizedBox(
                width: MediaQuery.textScalerOf(context).scale(16) > 24
                    ? 280
                    : 220,
                child: Material(
                  color: SolarColors.navy,
                  child: ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'FamilyApp',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      for (var index = 0; index < _destinations.length; index++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            selected: index == _index,
                            selectedTileColor: SolarColors.yellow,
                            leading: Icon(
                              _destinations[index].$1,
                              color: index == _index
                                  ? SolarColors.navy
                                  : Colors.white,
                            ),
                            title: Text(
                              _destinations[index].$2,
                              style: TextStyle(
                                color: index == _index
                                    ? SolarColors.navy
                                    : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => setState(() => _index = index),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '${auth.member?.name ?? ''} · ${auth.isParent ? 'Родитель' : 'Ребёнок'}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(key: const ValueKey('main-content'), child: content),
          ],
        ),
      ),
      floatingActionButton:
          _index == 0 || _index == 4 || (!auth.isParent && _index != 3)
          ? null
          : FloatingActionButton(
              tooltip: _index == 3
                  ? 'Добавить покупку'
                  : _index == 1
                  ? 'Добавить задачу'
                  : 'Добавить ограничение',
              onPressed: () => _index == 3
                  ? showHouseholdAction(context, HouseholdAction.shopping)
                  : _index == 1
                  ? _duties
                        ? showDutyDialog(context)
                        : showChoreDialog(context)
                  : showRestrictionDialog(context, store, controller),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.$1),
                    label: destination.$2,
                  ),
              ],
            ),
    );
  }
}

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
import 'package:familyapp/screens/shopping_page.dart';
import 'package:familyapp/dialogs/household_action_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  var _index = 0;
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
      ref.read(choreStoreProvider.notifier).refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      ref.read(choreStoreProvider.notifier).refresh();
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _notificationResponse(NotificationResponse response) async {
    if (!mounted) return;
    setState(() => _index = 2);
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

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(familyStoreProvider);
    final controller = ref.read(familyStoreProvider.notifier);
    final canManage = ref.watch(authStoreProvider).isParent;
    final pages = [
      CalendarPage(
        state: store,
        controller: controller,
        showChildFilter: canManage,
      ),
      RestrictionHistoryPage(state: store, controller: controller),
      const ChoresPage(),
      const ShoppingPage(),
      SettingsPage(state: store, controller: controller),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_index) {
          0 => 'Календарь',
          1 => 'Ограничения',
          2 => 'Регулярные задачи',
          3 => 'Покупки',
          _ => 'Настройки',
        }),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: store.loading
                ? null
                : () {
                    if (_index == 3) {
                      ref.read(shoppingStoreProvider.notifier).refresh();
                    }
                    controller.refresh();
                    ref.read(choreStoreProvider.notifier).refresh();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
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
            Expanded(child: pages[_index]),
          ],
        ),
      ),
      floatingActionButton: _index == 4 || (!canManage && _index != 3)
          ? null
          : MediaQuery.sizeOf(context).width < 600
          // Icon-only on phones: card actions are left-aligned, so a compact
          // button in the corner does not cover them.
          ? FloatingActionButton(
              tooltip: _index == 3
                  ? 'Добавить покупку'
                  : _index == 2
                  ? 'Добавить задачу'
                  : 'Добавить ограничение',
              onPressed: () => _index == 3
                  ? showHouseholdAction(context, HouseholdAction.shopping)
                  : _index == 2
                  ? showChoreDialog(context)
                  : showRestrictionDialog(context, store, controller),
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () => _index == 3
                  ? showHouseholdAction(context, HouseholdAction.shopping)
                  : _index == 2
                  ? showChoreDialog(context)
                  : showRestrictionDialog(context, store, controller),
              icon: const Icon(Icons.add),
              label: Text(
                _index == 3
                    ? 'Покупка'
                    : _index == 2
                    ? 'Задача'
                    : 'Ограничение',
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Календарь',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Ограничения',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            selectedIcon: Icon(Icons.task_alt),
            label: 'Задачи',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Покупки',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}

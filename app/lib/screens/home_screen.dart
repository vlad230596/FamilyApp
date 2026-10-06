import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/dialogs/restriction_dialog.dart';
import 'package:familyapp/screens/calendar_page.dart';
import 'package:familyapp/screens/restriction_history_page.dart';
import 'package:familyapp/screens/settings_page.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  var _index = 0;

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
      SettingsPage(state: store, controller: controller),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_index) {
          0 => 'Календарь',
          1 => 'Ограничения',
          _ => 'Настройки',
        }),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: store.loading ? null : controller.refresh,
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
      floatingActionButton: _index == 2 || !canManage
          ? null
          : MediaQuery.sizeOf(context).width < 600
          // Icon-only on phones: card actions are left-aligned, so a compact
          // button in the corner does not cover them.
          ? FloatingActionButton(
              tooltip: 'Добавить ограничение',
              onPressed: () =>
                  showRestrictionDialog(context, store, controller),
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () =>
                  showRestrictionDialog(context, store, controller),
              icon: const Icon(Icons.add),
              label: const Text('Ограничение'),
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
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}

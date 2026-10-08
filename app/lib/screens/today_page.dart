import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/dialogs/household_action_dialog.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/chore_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/state/household_store.dart';
import 'package:familyapp/theme/solar_theme.dart';
import 'package:familyapp/utils/dates.dart';
import 'package:familyapp/widgets/restriction_list_tile.dart';

/// A daily summary of server-authorized family data.
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStoreProvider);
    final duties = ref.watch(dutiesStoreProvider);
    final checks = ref.watch(choreStoreProvider);
    final family = ref.watch(familyStoreProvider);
    final shopping = ref.watch(shoppingStoreProvider);
    final today = dateToIso(DateTime.now());
    final occurrences = duties
        .rows('occurrences')
        .where(
          (item) => item['occurrence_date'] == today && item['away'] != true,
        )
        .toList();
    final dailyChecks = checks.chores
        .where(
          (item) =>
              item.active &&
              (item.dueDate == today ||
                  (item.nextAt != null &&
                      dateToIso(DateTime.parse(item.nextAt!).toLocal()) ==
                          today)),
        )
        .toList();
    final completed =
        occurrences.where((item) => item['status'] == 'confirmed').length +
        dailyChecks
            .where((item) => item.dueDate == today && item.dueAnswer != null)
            .length;
    final total = occurrences.length + dailyChecks.length;
    final pending = duties
        .rows('occurrences')
        .where((item) => item['status'] == 'pending' && item['away'] != true)
        .toList();
    final restrictions = family.restrictionsForDay(DateTime.now());
    final loading =
        duties.busy || checks.busy || shopping.busy || family.loading;
    final error = duties.error ?? checks.error ?? shopping.error;
    final hero = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SolarColors.yellow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
          final imageSize = constraints.maxWidth >= 460 ? 144.0 : 96.0;
          final house = ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/branding/familyapp-icon-1024.png',
              width: imageSize,
              height: imageSize,
              excludeFromSemantics: true,
            ),
          );
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Маленькие дела.\nУютный дом.',
                style: TextStyle(
                  fontSize: constraints.maxWidth >= 460 ? 28 : 22,
                  fontWeight: FontWeight.w800,
                  color: SolarColors.navy,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                loading
                    ? 'Обновляем день…'
                    : total == 0
                    ? 'Сегодня без обязательных дел'
                    : '$completed из $total дел завершено',
                style: const TextStyle(color: SolarColors.navy, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: loading
                      ? null
                      : total == 0
                      ? 0
                      : completed / total,
                  color: SolarColors.navy,
                  backgroundColor: SolarColors.navy.withValues(alpha: 0.12),
                  semanticsLabel: 'Выполненные дела',
                ),
              ),
            ],
          );
          return largeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summary,
                    const SizedBox(height: 16),
                    Align(alignment: Alignment.centerRight, child: house),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 16),
                    house,
                  ],
                );
        },
      ),
    );
    final tasks = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hero,
        const SizedBox(height: 16),
        _heading(
          context,
          'Дела на сегодня',
          Icons.task_alt_outlined,
          () => onNavigate(1),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: CardTheme(
            data: Theme.of(context).cardTheme.copyWith(
              margin: EdgeInsets.zero,
              shape: const RoundedRectangleBorder(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (occurrences.isEmpty && dailyChecks.isEmpty && !loading)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('На сегодня всё свободно'),
                    ),
                  ),
                for (final item in occurrences)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: _symbol(
                              item['status'] == 'confirmed'
                                  ? Icons.check_circle_outline
                                  : item['status'] == 'pending'
                                  ? Icons.hourglass_top_outlined
                                  : Icons.cleaning_services_outlined,
                            ),
                            title: Text(
                              item['title'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${item['assigned_name'] ?? 'Без назначения'} · ${switch (item['status']) {
                                'confirmed' => 'Выполнено',
                                'pending' => 'На проверке',
                                'rejected' => 'На доработку',
                                _ => 'Ожидает',
                              }}',
                            ),
                          ),
                          if (item['status'] == 'open' ||
                              item['status'] == 'rejected')
                            FilledButton.icon(
                              onPressed: duties.busy
                                  ? null
                                  : () => showHouseholdAction(
                                      context,
                                      HouseholdAction.complete,
                                      item: item,
                                    ),
                              icon: const Icon(Icons.check),
                              label: const Text('Выполнено'),
                            ),
                        ],
                      ),
                    ),
                  ),
                for (final chore in dailyChecks)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: _symbol(Icons.fact_check_outlined),
                            title: Text(
                              chore.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${chore.responsibleName} · ${chore.dueDate != today
                                  ? 'В ${chore.reminderTime}'
                                  : chore.dueAnswer == null
                                  ? 'Проверка'
                                  : chore.dueAnswer!
                                  ? 'Да'
                                  : 'Нет'}',
                            ),
                          ),
                          if (chore.dueDate == today &&
                              chore.dueAnswer == null &&
                              chore.responsibleMemberId == auth.member?.id)
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: checks.busy
                                      ? null
                                      : () => ref
                                            .read(choreStoreProvider.notifier)
                                            .answer(
                                              chore.id,
                                              chore.dueDate!,
                                              true,
                                              chore.revision,
                                            ),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Да'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: checks.busy
                                      ? null
                                      : () => ref
                                            .read(choreStoreProvider.notifier)
                                            .answer(
                                              chore.id,
                                              chore.dueDate!,
                                              false,
                                              chore.revision,
                                            ),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Нет'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    final aside = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (auth.isParent && pending.isNotEmpty) ...[
          _heading(
            context,
            'Ждут подтверждения',
            Icons.hourglass_top_outlined,
            () => onNavigate(1),
          ),
          for (final item in pending)
            Card(
              color: SolarColors.navy,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title'] as String,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    Text(
                      '${item['performer_name'] ?? item['assigned_name'] ?? 'Участник'} · ${formatDate(DateTime.parse(item['occurrence_date']))}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: SolarColors.yellow,
                        foregroundColor: SolarColors.navy,
                      ),
                      onPressed: duties.busy
                          ? null
                          : () => showHouseholdAction(
                              context,
                              HouseholdAction.review,
                              item: item,
                            ),
                      child: const Text('Рассмотреть'),
                    ),
                  ],
                ),
              ),
            ),
        ],
        _heading(
          context,
          'Ограничения',
          Icons.event_outlined,
          () => onNavigate(2),
        ),
        if (restrictions.isEmpty && !family.loading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Сегодня ограничений нет'),
            ),
          ),
        for (final item in restrictions)
          RestrictionListTile(
            restriction: item,
            controller: ref.read(familyStoreProvider.notifier),
          ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: _symbol(Icons.shopping_bag_outlined),
            title: const Text('Заглянем в магазин?'),
            subtitle: Text(
              shopping.busy
                  ? 'Загрузка списка…'
                  : '${shopping.rows('items').length} в списке покупок',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onNavigate(3),
          ),
        ),
      ],
    );
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref.read(familyStoreProvider.notifier).refresh(),
          ref.read(dutiesStoreProvider.notifier).refresh(),
          ref.read(choreStoreProvider.notifier).refresh(),
          ref.read(shoppingStoreProvider.notifier).refresh(),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            'Привет, ${auth.member?.name ?? 'семья'}!',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            formatDate(DateTime.now()),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          if (error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(error),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >= 760 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 24
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: tasks),
                      const SizedBox(width: 24),
                      Expanded(flex: 2, child: aside),
                    ],
                  )
                : Column(children: [tasks, const SizedBox(height: 16), aside]),
          ),
        ],
      ),
    );
  }

  Widget _symbol(IconData icon) => CircleAvatar(
    backgroundColor: SolarColors.background,
    foregroundColor: SolarColors.navy,
    child: Icon(icon),
  );
  Widget _heading(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Открыть: $title',
          onPressed: action,
          icon: const Icon(Icons.arrow_forward),
        ),
      ],
    ),
  );
}

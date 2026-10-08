import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/dialogs/household_action_dialog.dart';
import 'package:familyapp/state/household_store.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/utils/dates.dart';

class ShoppingPage extends ConsumerStatefulWidget {
  const ShoppingPage({super.key});
  @override
  ConsumerState<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends ConsumerState<ShoppingPage> {
  bool _history = false;
  Future<void> _editList({Map<String, dynamic>? list}) async {
    final form = GlobalKey<FormState>();
    var value = list?['name'] as String? ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(list == null ? 'Новый список' : 'Название списка'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: value,
            onChanged: (text) => value = text,
            validator: (text) => text == null || text.trim().isEmpty
                ? '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043d\u0430\u0437\u0432\u0430\u043d\u0438\u0435'
                : null,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, value.trim());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    await ref
        .read(shoppingStoreProvider.notifier)
        .run(
          (api) => api.saveShoppingList(name, id: list?['id'] as int?),
          mutation: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shoppingStoreProvider);
    final store = ref.read(shoppingStoreProvider.notifier);
    final lists = state.rows('lists');
    final selected = lists
        .where((list) => list['id'] == state.data['list_id'])
        .firstOrNull;
    final parent = ref.watch(authStoreProvider).isParent;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: RefreshIndicator(
          onRefresh: store.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (lists.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey(state.data['list_id']),
                  initialValue: state.data['list_id'] as int?,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Список покупок',
                  ),
                  items: [
                    for (final list in lists)
                      DropdownMenuItem(
                        value: list['id'] as int,
                        child: Text(
                          '${list['name']}${list['is_main'] == 1 ? ' · Главный' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: state.busy
                      ? null
                      : (id) {
                          if (id != null) store.selectList(id);
                        },
                ),
                if (selected?['is_main'] == 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Главный семейный список'),
                  ),
                if (parent)
                  ExpansionTile(
                    title: const Text('Управление списками'),
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: state.busy ? null : () => _editList(),
                            icon: const Icon(Icons.add),
                            label: const Text('Новый список'),
                          ),
                          TextButton(
                            onPressed: state.busy || selected == null
                                ? null
                                : () => _editList(list: selected),
                            child: const Text('Переименовать'),
                          ),
                          if (selected != null && selected['is_main'] != 1)
                            TextButton.icon(
                              onPressed: state.busy
                                  ? null
                                  : () => store.run(
                                      (api) => api.saveShoppingList(
                                        selected['name'] as String,
                                        id: selected['id'] as int,
                                        main: true,
                                      ),
                                      mutation: true,
                                    ),
                              icon: const Icon(Icons.star_outline),
                              label: const Text('Сделать главным'),
                            ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
              ],
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Список'),
                    selected: !_history,
                    onSelected: (_) => setState(() => _history = false),
                  ),
                  ChoiceChip(
                    label: const Text('Купленное'),
                    selected: _history,
                    onSelected: (_) => setState(() => _history = true),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (state.busy) const LinearProgressIndicator(),
              if (state.error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(state.error!),
                  ),
                ),
              if (!_history) ...[
                if (state.rows('items').isEmpty && !state.busy)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Список покупок пуст. Добавьте то, что нужно семье.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final urgency in ['urgent', 'week', 'background'])
                  if (state
                      .rows('items')
                      .any((item) => item['urgency'] == urgency)) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        urgencyLabels[urgency]!,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    for (final category
                        in (state
                            .rows('items')
                            .where((item) => item['urgency'] == urgency)
                            .map((item) => item['category'] as String)
                            .toSet()
                            .toList()
                          ..sort())) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          category.isEmpty ? 'Без категории' : category,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      for (final item
                          in state
                              .rows('items')
                              .where(
                                (item) =>
                                    item['urgency'] == urgency &&
                                    item['category'] == category,
                              ))
                        Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: IconButton(
                              tooltip: 'Куплено: ${item['name']}',
                              icon: const Icon(Icons.check_box_outline_blank),
                              onPressed: state.busy
                                  ? null
                                  : () => showHouseholdAction(
                                      context,
                                      HouseholdAction.buy,
                                      item: item,
                                    ),
                            ),
                            title: Text(
                              item['name'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            subtitle: item['category'] == ''
                                ? null
                                : Text(item['category'] as String),
                            onTap: state.busy
                                ? null
                                : () => showHouseholdAction(
                                    context,
                                    HouseholdAction.buy,
                                    item: item,
                                  ),
                          ),
                        ),
                    ],
                  ],
                const ExpansionTile(
                  title: Text('Как работает срочность'),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '«Когда-нибудь» переходит в «На этой неделе» через 30 дней. Автоматически срочными покупки не становятся.',
                      ),
                    ),
                  ],
                ),
              ] else ...[
                if (state.rows('purchases').isEmpty && !state.busy)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('История покупок пока пуста.'),
                  ),
                for (final item in state.rows('purchases'))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${formatDate(DateTime.parse(item['bought_at']))} · ${item['bought_by_name']}',
                          ),
                          if (item['returned_at'] != null)
                            const Text('Возвращено в список')
                          else if (item['return_at'] != null &&
                              item['return_cancelled_at'] == null)
                            Text(
                              'Вернётся ${formatDate(DateTime.parse(item['return_at']))}',
                            ),
                          if (item['return_cancelled_at'] != null &&
                              item['returned_at'] == null)
                            const Text('Автовозврат отменён'),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (item['returned_at'] == null)
                                TextButton(
                                  onPressed: state.busy
                                      ? null
                                      : () => store.run(
                                          (api) => api.returnShopping(
                                            item['id'] as int,
                                          ),
                                          mutation: true,
                                        ),
                                  child: const Text('Вернуть сейчас'),
                                ),
                              if (item['return_at'] != null &&
                                  item['returned_at'] == null &&
                                  item['return_cancelled_at'] == null)
                                TextButton(
                                  onPressed: state.busy
                                      ? null
                                      : () => store.run(
                                          (api) => api.returnShopping(
                                            item['id'] as int,
                                            cancel: true,
                                          ),
                                          mutation: true,
                                        ),
                                  child: const Text('Отменить автовозврат'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

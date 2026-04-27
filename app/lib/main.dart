import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:5055',
);

void main() {
  runApp(const ProviderScope(child: FamilyApp()));
}

final apiClientProvider = Provider((ref) => ApiClient(apiBaseUrl));

final familyStoreProvider = NotifierProvider<FamilyStore, FamilyState>(
  FamilyStore.new,
);

class FamilyApp extends StatelessWidget {
  const FamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F7D58)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(familyStoreProvider);
    final controller = ref.read(familyStoreProvider.notifier);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('FamilyApp'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.child_care), text: 'Дети'),
              Tab(icon: Icon(Icons.event_busy), text: 'Ограничения'),
            ],
          ),
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
              Expanded(
                child: TabBarView(
                  children: [
                    ChildrenTab(state: store),
                    RestrictionsTab(state: store, controller: controller),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: Builder(
          builder: (context) {
            final tabController = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tabController.animation ?? tabController,
              builder: (context, _) {
                final tabIndex = tabController.index;
                return FloatingActionButton.extended(
                  onPressed: () {
                    if (tabIndex == 0) {
                      showChildDialog(context, controller);
                    } else {
                      showRestrictionDialog(context, store, controller);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tabIndex == 0 ? 'Ребёнок' : 'Ограничение'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class ChildrenTab extends StatelessWidget {
  const ChildrenTab({required this.state, super.key});

  final FamilyState state;

  @override
  Widget build(BuildContext context) {
    if (state.children.isEmpty) {
      return const EmptyState(
        icon: Icons.child_care,
        title: 'Добавьте ребёнка',
        message: 'После этого можно будет назначать ограничения.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final child = state.children[index];
        final activeCount = state.restrictions
            .where(
              (item) => item.childId == child.id && item.status == 'active',
            )
            .length;
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(child.name),
            subtitle: Text(
              activeCount == 0
                  ? 'Активных ограничений нет'
                  : 'Активных ограничений: $activeCount',
            ),
          ),
        );
      },
    );
  }
}

class RestrictionsTab extends StatelessWidget {
  const RestrictionsTab({
    required this.state,
    required this.controller,
    super.key,
  });

  final FamilyState state;
  final FamilyStore controller;

  @override
  Widget build(BuildContext context) {
    if (state.restrictions.isEmpty) {
      return const EmptyState(
        icon: Icons.event_available,
        title: 'Ограничений пока нет',
        message: 'Создайте первое ограничение для выбранного ребёнка.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.restrictions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final restriction = state.restrictions[index];
        final active = restriction.status == 'active';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        restriction.childName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    StatusChip(status: restriction.status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(restriction.reason),
                const SizedBox(height: 8),
                Text(
                  '${formatDate(restriction.startDate)} - ${formatDate(restriction.endDate)}',
                ),
                if (active) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            showExtendDialog(context, controller, restriction),
                        icon: const Icon(Icons.update),
                        label: const Text('Продлить'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            showCancelDialog(context, controller, restriction),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Отменить'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'active' => 'Активно',
      'cancelled' => 'Отменено',
      'expired' => 'Истекло',
      _ => status,
    };
    return Chip(label: Text(label));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class FamilyState {
  const FamilyState({
    this.children = const [],
    this.restrictions = const [],
    this.loading = false,
    this.error,
  });

  final List<Child> children;
  final List<Restriction> restrictions;
  final bool loading;
  final String? error;

  FamilyState copyWith({
    List<Child>? children,
    List<Restriction>? restrictions,
    bool? loading,
    Object? error = _unchanged,
  }) {
    return FamilyState(
      children: children ?? this.children,
      restrictions: restrictions ?? this.restrictions,
      loading: loading ?? this.loading,
      error: error == _unchanged ? this.error : error as String?,
    );
  }
}

const _unchanged = Object();

class FamilyStore extends Notifier<FamilyState> {
  late final ApiClient _api;
  var _started = false;

  @override
  FamilyState build() {
    _api = ref.watch(apiClientProvider);
    if (!_started) {
      _started = true;
      Future.microtask(refresh);
    }
    return const FamilyState();
  }

  Future<void> refresh() async {
    await _run(() async {
      final children = await _api.listChildren();
      final restrictions = await _api.listRestrictions();
      state = state.copyWith(children: children, restrictions: restrictions);
    });
  }

  Future<void> createChild(String name) async {
    await _run(() async {
      await _api.createChild(name);
      final children = await _api.listChildren();
      state = state.copyWith(children: children);
    });
  }

  Future<void> createRestriction({
    required int childId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    await _run(() async {
      await _api.createRestriction(
        childId: childId,
        startDate: startDate,
        endDate: endDate,
        reason: reason,
      );
      final restrictions = await _api.listRestrictions();
      state = state.copyWith(restrictions: restrictions);
    });
  }

  Future<void> extendRestriction(int id, DateTime newEndDate) async {
    await _run(() async {
      await _api.extendRestriction(id, newEndDate);
      final restrictions = await _api.listRestrictions();
      state = state.copyWith(restrictions: restrictions);
    });
  }

  Future<void> cancelRestriction(int id, String note) async {
    await _run(() async {
      await _api.cancelRestriction(id, note);
      final restrictions = await _api.listRestrictions();
      state = state.copyWith(restrictions: restrictions);
    });
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void showError(String message) {
    state = state.copyWith(error: message);
  }

  Future<void> _run(Future<void> Function() action) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await action();
    } catch (exception) {
      state = state.copyWith(error: exception.toString());
    } finally {
      state = state.copyWith(loading: false);
    }
  }
}

class ApiClient {
  ApiClient(String baseUrl) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;

  Future<List<Child>> listChildren() async {
    final data = await _get('/api/children');
    return (data['children'] as List)
        .map((item) => Child.fromJson(item))
        .toList();
  }

  Future<void> createChild(String name) async {
    await _post('/api/children', {'name': name});
  }

  Future<List<Restriction>> listRestrictions() async {
    final data = await _get('/api/restrictions');
    return (data['restrictions'] as List)
        .map((item) => Restriction.fromJson(item))
        .toList();
  }

  Future<void> createRestriction({
    required int childId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    await _post('/api/restrictions', {
      'child_id': childId,
      'start_date': dateToIso(startDate),
      'end_date': dateToIso(endDate),
      'reason': reason,
    });
  }

  Future<void> extendRestriction(int id, DateTime newEndDate) async {
    await _post('/api/restrictions/$id/extend', {
      'new_end_date': dateToIso(newEndDate),
    });
  }

  Future<void> cancelRestriction(int id, String note) async {
    await _post('/api/restrictions/$id/cancel', {'note': note});
  }

  Future<Map<String, dynamic>> _get(String path) async {
    return _send(() => http.get(_baseUri.resolve(path)));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    return _send(
      () => http.post(
        _baseUri.resolve(path),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    late final http.Response response;
    try {
      response = await request();
    } on ClientException {
      throw Exception('Сервер не подключён. Запустите backend на $_baseUri.');
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw Exception(
        'Backend вернул не JSON. Проверьте, что Flask запущен на $_baseUri.',
      );
    }

    final data = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Ошибка сервера');
    }
    return data;
  }
}

class Child {
  Child({required this.id, required this.name});

  final int id;
  final String name;

  factory Child.fromJson(dynamic json) {
    return Child(id: json['id'] as int, name: json['name'] as String);
  }
}

class Restriction {
  Restriction({
    required this.id,
    required this.childId,
    required this.childName,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
  });

  final int id;
  final int childId;
  final String childName;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status;

  factory Restriction.fromJson(dynamic json) {
    return Restriction(
      id: json['id'] as int,
      childId: json['child_id'] as int,
      childName: json['child_name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      reason: json['reason'] as String,
      status: json['status'] as String,
    );
  }
}

Future<void> showChildDialog(BuildContext context, FamilyStore store) async {
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Новый ребёнок'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Имя'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () async {
            await store.createChild(controller.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Добавить'),
        ),
      ],
    ),
  );
}

Future<void> showRestrictionDialog(
  BuildContext context,
  FamilyState state,
  FamilyStore store,
) async {
  if (state.children.isEmpty) {
    store.showError('Сначала добавьте ребёнка.');
    return;
  }

  var selectedChildId = state.children.first.id;
  var startDate = DateTime.now();
  var endDate = DateTime.now().add(const Duration(days: 1));
  final reasonController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Новое ограничение'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: selectedChildId,
                decoration: const InputDecoration(labelText: 'Ребёнок'),
                items: state.children
                    .map(
                      (child) => DropdownMenuItem(
                        value: child.id,
                        child: Text(child.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => selectedChildId = value ?? selectedChildId),
              ),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Причина'),
              ),
              const SizedBox(height: 12),
              DateRow(
                label: 'Начало',
                value: startDate,
                onTap: () async {
                  final picked = await pickDate(context, startDate);
                  if (picked != null) setState(() => startDate = picked);
                },
              ),
              DateRow(
                label: 'Конец',
                value: endDate,
                onTap: () async {
                  final picked = await pickDate(context, endDate);
                  if (picked != null) setState(() => endDate = picked);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              await store.createRestriction(
                childId: selectedChildId,
                startDate: startDate,
                endDate: endDate,
                reason: reasonController.text,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showExtendDialog(
  BuildContext context,
  FamilyStore store,
  Restriction restriction,
) async {
  var newEndDate = restriction.endDate.add(const Duration(days: 1));
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Продлить ограничение'),
        content: DateRow(
          label: 'Новая дата окончания',
          value: newEndDate,
          onTap: () async {
            final picked = await pickDate(context, newEndDate);
            if (picked != null) setState(() => newEndDate = picked);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              await store.extendRestriction(restriction.id, newEndDate);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Продлить'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCancelDialog(
  BuildContext context,
  FamilyStore store,
  Restriction restriction,
) async {
  final noteController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Отменить ограничение'),
      content: TextField(
        controller: noteController,
        decoration: const InputDecoration(labelText: 'Комментарий'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Нет'),
        ),
        FilledButton(
          onPressed: () async {
            await store.cancelRestriction(restriction.id, noteController.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Отменить'),
        ),
      ],
    ),
  );
}

class DateRow extends StatelessWidget {
  const DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(formatDate(value)),
      trailing: const Icon(Icons.calendar_month),
      onTap: onTap,
    );
  }
}

Future<DateTime?> pickDate(BuildContext context, DateTime initialDate) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
  );
}

String dateToIso(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String formatDate(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.'
      '${value.year}';
}

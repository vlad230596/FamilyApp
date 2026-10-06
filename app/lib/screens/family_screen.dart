import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';

class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});
  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _createForm = GlobalKey<FormState>();
  final _joinForm = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStoreProvider);
    final store = ref.read(authStoreProvider.notifier);
    final api = ref.read(apiClientProvider);
    final families = auth.account?['families'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя семья'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: auth.busy ? null : store.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Здравствуйте, ${auth.account?['user']?['name'] ?? ''}!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  for (final family in families)
                    ListTile(
                      leading: const Icon(Icons.family_restroom),
                      title: Text(family['name'] as String),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: auth.busy
                          ? null
                          : () => store.familyAction(
                              () => api.selectFamily(family['id'] as int),
                            ),
                    ),
                  const SizedBox(height: 16),
                  Form(
                    key: _createForm,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Название семьи',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Введите название'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: auth.busy
                              ? null
                              : () {
                                  if (_createForm.currentState!.validate()) {
                                    store.familyAction(
                                      () => api.createFamily(_name.text.trim()),
                                    );
                                  }
                                },
                          child: const Text('Создать семью'),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(),
                  ),
                  const Text(
                    'Есть приглашение? Введите код, который передал родитель.',
                  ),
                  const SizedBox(height: 12),
                  Form(
                    key: _joinForm,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _code,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Код приглашения',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Введите код'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: auth.busy
                              ? null
                              : () {
                                  if (_joinForm.currentState!.validate()) {
                                    store.familyAction(
                                      () => api.acceptInvitation(
                                        _code.text.trim(),
                                      ),
                                    );
                                  }
                                },
                          child: const Text('Присоединиться'),
                        ),
                      ],
                    ),
                  ),
                  if (auth.busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        auth.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

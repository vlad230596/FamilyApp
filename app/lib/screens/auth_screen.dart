import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/state/auth_store.dart';

/// Login and independent account registration.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _name = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _localError;
  bool _register = false;

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(authStoreProvider).busy) return;
    final store = ref.read(authStoreProvider.notifier);
    if (_register) {
      final error = _name.text.trim().isEmpty
          ? 'Введите имя'
          : _password.text != _repeat.text
          ? 'Пароли не совпадают'
          : null;
      setState(() => _localError = error);
      if (error != null) return;
      await store.register(_name.text, _login.text, _password.text);
    } else {
      setState(() => _localError = null);
      await store.login(_login.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStoreProvider);
    final error = _localError ?? auth.error;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.family_restroom,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _register ? 'Регистрация' : 'Вход',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (_register) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Создайте аккаунт, затем создайте семью или примите приглашение.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Имя'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _login,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Логин'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: _register
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: _register ? null : (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Пароль'),
                    ),
                    if (_register) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _repeat,
                        obscureText: true,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Повторите пароль',
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: auth.busy ? null : _submit,
                      child: auth.busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? 'Создать аккаунт' : 'Войти'),
                    ),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _localError = null;
                            }),
                      child: Text(
                        _register
                            ? 'Уже есть аккаунт? Войти'
                            : 'Зарегистрироваться',
                      ),
                    ),
                    if (!_register) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: auth.busy
                            ? null
                            : ref.read(authStoreProvider.notifier).restore,
                        child: const Text('Проверить подключение'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

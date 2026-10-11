import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'package:familyapp/services/background_reminder_sync.dart';
import 'package:familyapp/services/local_storage.dart';

/// Persists the session token between app launches.
class TokenStorage {
  static const _key = 'session_token';
  final _storage = const FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  Future<void> delete() => _storage.delete(key: _key);
}

final tokenStorageProvider = Provider((ref) => TokenStorage());

final authStoreProvider = NotifierProvider<AuthStore, AuthState>(AuthStore.new);

enum AuthStatus { checking, familyRequired, signedOut, signedIn }

class AuthState {
  const AuthState({
    this.status = AuthStatus.checking,
    this.member,
    this.account,
    this.busy = false,
    this.error,
  });

  final AuthStatus status;
  final Member? member;
  final Map<String, dynamic>? account;
  final bool busy;
  final String? error;

  bool get isParent => member?.isParent ?? false;
}

class AuthStore extends Notifier<AuthState> {
  var _started = false;
  Future<void> _accountWrites = Future.value();

  @override
  AuthState build() {
    if (!_started) {
      _started = true;
      Future.microtask(restore);
    }
    return const AuthState();
  }

  /// Restores a saved account session and its selected family.
  Future<void> restore() async {
    final api = ref.read(apiClientProvider);
    api.onUnauthorized = _onUnauthorized;
    state = const AuthState(busy: true);
    try {
      final token = await ref.read(tokenStorageProvider).read();
      if (token != null) {
        api.token = token;
        Map<String, dynamic>? cached;
        try {
          final saved = await ref
              .read(localStorageProvider)
              .read('offline_account_v1');
          if (saved != null) {
            final data = jsonDecode(saved) as Map<String, dynamic>;
            if (data['session_token'] == token) {
              cached = data['account'] as Map<String, dynamic>;
            }
          }
        } catch (_) {
          // A missing/unreadable cache must not prevent online sign-in.
        }
        if (cached != null) await _applyAccount(cached, persist: false);
        try {
          final account = await api.accountState();
          if (!ref.mounted || api.token != token) return;
          await _applyAccount(account);
          return;
        } on UnauthorizedException {
          await ref.read(tokenStorageProvider).delete();
          api.token = null;
        } on Exception {
          if (cached != null && api.token == token) return;
          api.token = null;
        }
      }
      state = const AuthState(status: AuthStatus.signedOut);
      await _clearReminders();
    } catch (exception) {
      state = AuthState(
        status: AuthStatus.signedOut,
        error: exception.toString(),
      );
      await _clearReminders();
    }
  }

  Future<void> login(String login, String password) async {
    await _authenticate(
      () => ref.read(apiClientProvider).login(login.trim(), password),
    );
  }

  Future<void> register(String name, String login, String password) async {
    await _authenticate(
      () => ref
          .read(apiClientProvider)
          .register(name.trim(), login.trim(), password),
    );
  }

  Future<void> logout() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.logout();
    } catch (_) {
      // Signing out locally is enough when the server is unreachable.
    }
    await _clearSession();
  }

  /// Refreshes the signed-in member after their profile was edited.
  Future<void> reloadMember() async {
    await _applyAccount(await ref.read(apiClientProvider).accountState());
  }

  Future<void> _authenticate(Future<AuthResult> Function() request) async {
    final api = ref.read(apiClientProvider);
    state = AuthState(
      status: state.status,
      member: state.member,
      account: state.account,
      busy: true,
    );
    try {
      api.token = null;
      final result = await request();
      api.token = result.token;
      await ref.read(tokenStorageProvider).write(api.token!);
      ref.invalidate(familyStoreProvider);
      await _applyAccount(result.account!);
    } catch (exception) {
      state = AuthState(
        status: state.status,
        member: state.member,
        account: state.account,
        error: _message(exception),
      );
    }
  }

  void chooseFamily() {
    _clearReminders();
    state = AuthState(
      status: AuthStatus.familyRequired,
      account: state.account,
    );
  }

  Future<void> _applyAccount(
    Map<String, dynamic> data, {
    bool persist = true,
  }) async {
    final member = data['member'] == null
        ? null
        : Member.fromJson(data['member']);
    final changedMember =
        state.member != null && state.member?.id != member?.id;
    state = AuthState(
      status: member == null ? AuthStatus.familyRequired : AuthStatus.signedIn,
      member: member,
      account: data,
    );
    // A normal restore keeps visible unanswered alerts. Sync filters their owner.
    if (changedMember || member == null) _clearReminders();
    ref.invalidate(familyStoreProvider);
    if (persist) {
      final token = ref.read(apiClientProvider).token;
      final storage = ref.read(localStorageProvider);
      final next = _accountWrites.then((_) async {
        if (ref.mounted &&
            token != null &&
            ref.read(apiClientProvider).token == token) {
          await storage.write(
            'offline_account_v1',
            jsonEncode({'session_token': token, 'account': data}),
          );
        }
      });
      _accountWrites = next.catchError((Object _) {});
      await _accountWrites;
    }
  }

  Future<void> familyAction(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    state = AuthState(
      status: state.status,
      member: state.member,
      account: state.account,
      busy: true,
    );
    try {
      await _applyAccount(await action());
    } catch (exception) {
      state = AuthState(
        status: state.status,
        member: state.member,
        account: state.account,
        error: _message(exception),
      );
    }
  }

  void _onUnauthorized() {
    if (state.status == AuthStatus.signedIn ||
        state.status == AuthStatus.familyRequired) {
      _clearSession(error: 'Сессия завершена. Войдите снова.');
    }
  }

  Future<void> _clearSession({String? error}) async {
    ref.read(apiClientProvider).token = null;
    // Invalidate in-flight task syncs before awaiting platform cancellation.
    state = AuthState(status: AuthStatus.signedOut, error: error);
    await _clearReminders();
    await ref.read(tokenStorageProvider).delete();
    await _accountWrites;
    await ref.read(localStorageProvider).delete('offline_account_v1');
    ref.invalidate(familyStoreProvider);
  }

  Future<void> _clearReminders() async {
    try {
      await ref.read(backgroundReminderSyncProvider).clear();
    } catch (_) {
      // Notification cancellation is still needed if native work is unavailable.
    }
    try {
      await ref.read(choreNotificationsProvider).clear();
    } catch (_) {
      // Local authentication must still work if notifications are unavailable.
    }
  }
}

String _message(Object exception) {
  final text = exception.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

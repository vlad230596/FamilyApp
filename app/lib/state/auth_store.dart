import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/services/chore_notifications.dart';
import 'package:familyapp/services/background_reminder_sync.dart';

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
        try {
          _applyAccount(await api.accountState());
          return;
        } on UnauthorizedException {
          await ref.read(tokenStorageProvider).delete();
          api.token = null;
        } on Exception {
          // Server unreachable: keep the saved token and retry on next check.
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
    _applyAccount(await ref.read(apiClientProvider).accountState());
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
      _applyAccount(result.account!);
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

  void _applyAccount(Map<String, dynamic> data) {
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
      _applyAccount(await action());
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

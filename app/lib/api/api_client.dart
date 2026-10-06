import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:familyapp/models/child.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/models/restriction.dart';
import 'package:familyapp/models/restriction_type.dart';
import 'package:familyapp/utils/dates.dart';

/// Thrown when the server rejects the session token.
class UnauthorizedException implements Exception {
  UnauthorizedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Result of a successful login or registration.
class AuthResult {
  AuthResult(this.token, this.member);

  final String token;
  final Member? member;
  Map<String, dynamic>? account;
}

class ApiClient {
  ApiClient(String baseUrl) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;

  /// Session token sent as a bearer token with every request.
  String? token;

  /// Called when an authenticated request gets 401, e.g. after the session was
  /// revoked by a password change on another device.
  void Function()? onUnauthorized;

  AuthResult _authResult(Map<String, dynamic> data) => AuthResult(
    data['token'] as String,
    data['member'] == null ? null : Member.fromJson(data['member']),
  )..account = data;

  Future<AuthResult> register(
    String name,
    String login,
    String password,
  ) async => _authResult(
    await _post('/api/auth/register', {
      'name': name,
      'login': login,
      'password': password,
    }),
  );

  Future<AuthResult> login(String login, String password) async => _authResult(
    await _post('/api/auth/login', {'login': login, 'password': password}),
  );

  Future<Map<String, dynamic>> accountState() => _get('/api/me');
  Future<Map<String, dynamic>> createFamily(String name) =>
      _post('/api/families', {'name': name});
  Future<Map<String, dynamic>> selectFamily(int id) =>
      _post('/api/families/$id/select', {});
  Future<Map<String, dynamic>> acceptInvitation(String code) =>
      _post('/api/invitations/accept', {'code': code});
  Future<Map<String, dynamic>> createInvitation({
    String role = 'parent',
    int? memberId,
  }) => _post('/api/invitations', {'role': role, 'member_id': ?memberId});

  Future<void> logout() async {
    await _post('/api/auth/logout', {});
  }

  Future<Member> me() async {
    final data = await _get('/api/me');
    return Member.fromJson(data['member']);
  }

  Future<List<Member>> listMembers() async {
    final data = await _get('/api/members');
    return (data['members'] as List)
        .map((item) => Member.fromJson(item))
        .toList();
  }

  Future<void> createMember({
    required String name,
    required String icon,
    required String role,
    String? login,
    String? password,
  }) async {
    final body = <String, dynamic>{'name': name, 'icon': icon, 'role': role};
    if (login != null && login.isNotEmpty) {
      body['login'] = login;
      body['password'] = password;
    }
    await _post('/api/members', body);
  }

  Future<void> updateMember(int id, String name, String icon) async {
    await _post('/api/members/$id', {'name': name, 'icon': icon});
  }

  Future<void> setCredentials(int id, String login, String password) async {
    await _post('/api/members/$id/credentials', {
      'login': login,
      'password': password,
    });
  }

  Future<List<Child>> listChildren() async {
    final data = await _get('/api/children');
    return (data['children'] as List)
        .map((item) => Child.fromJson(item))
        .toList();
  }

  Future<List<RestrictionType>> listRestrictionTypes() async {
    final data = await _get('/api/restriction-types');
    return (data['restriction_types'] as List)
        .map((item) => RestrictionType.fromJson(item))
        .toList();
  }

  Future<void> createRestrictionType(String name, String color) async {
    await _post('/api/restriction-types', {'name': name, 'color': color});
  }

  Future<void> archiveRestrictionType(int id) async {
    await _post('/api/restriction-types/$id/archive', {});
  }

  Future<List<Restriction>> listRestrictions() async {
    final data = await _get('/api/restrictions');
    return (data['restrictions'] as List)
        .map((item) => Restriction.fromJson(item))
        .toList();
  }

  Future<List<Restriction>> listRestrictionsForRange(
    DateTime start,
    DateTime end,
  ) async {
    final data = await _get(
      '/api/restrictions/range?start_date=${dateToIso(start)}&end_date=${dateToIso(end)}',
    );
    return (data['restrictions'] as List)
        .map((item) => Restriction.fromJson(item))
        .toList();
  }

  Future<void> createRestriction({
    required int childId,
    required DateTime startDate,
    required int durationCount,
    required String durationUnit,
    int? restrictionTypeId,
    String? customTypeName,
    required String color,
    required String reason,
  }) async {
    final body = {
      'child_id': childId,
      'start_date': dateToIso(startDate),
      'duration_count': durationCount,
      'duration_unit': durationUnit,
      'color': color,
      'reason': reason,
    };
    if (restrictionTypeId != null) {
      body['restriction_type_id'] = restrictionTypeId;
    }
    if (customTypeName != null) {
      body['custom_type_name'] = customTypeName;
    }
    await _post('/api/restrictions', body);
  }

  Future<void> extendRestriction(int id, DateTime newEndDate) async {
    await _post('/api/restrictions/$id/extend', {
      'new_end_date': dateToIso(newEndDate),
    });
  }

  Future<void> cancelRestriction(int id, String note) async {
    await _post('/api/restrictions/$id/cancel', {'note': note});
  }

  Map<String, String> get _authHeaders {
    final currentToken = token;
    return currentToken == null
        ? {}
        : {'Authorization': 'Bearer $currentToken'};
  }

  Future<Map<String, dynamic>> _get(String path) async {
    return _send(() => http.get(_baseUri.resolve(path), headers: _authHeaders));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    return _send(
      () => http.post(
        _baseUri.resolve(path),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
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
      throw Exception('Сервер не подключен. Запустите backend на $_baseUri.');
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw Exception('Backend вернул не JSON. Проверьте Flask на $_baseUri.');
    }

    final data = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode == 401) {
      final hadToken = token != null;
      if (hadToken) onUnauthorized?.call();
      throw UnauthorizedException(
        hadToken
            ? 'Сессия завершена. Войдите снова.'
            : 'Неверный логин или пароль.',
      );
    }
    if (response.statusCode == 403) {
      final error = data['error'] as String?;
      throw Exception(
        _errorTranslations[error] ?? 'Это действие доступно только родителям.',
      );
    }
    if (response.statusCode >= 400) {
      final error = data['error'] as String?;
      throw Exception(_errorTranslations[error] ?? error ?? 'Ошибка сервера');
    }
    return data;
  }
}

const _errorTranslations = {
  'invitation invalid or expired':
      'Приглашение недействительно или срок действия истёк.',
  'already a family member': 'Вы уже состоите в этой семье.',
  'member already has an account': 'Участник уже связан с аккаунтом.',
  'family selection required': 'Сначала выберите семью.',
  'family access denied': 'У вас нет доступа к этой семье.',
  'only account owner may change credentials':
      'Пароль может менять только владелец аккаунта.',
  'use an invitation to link an account':
      'Для подключения аккаунта создайте приглашение.',
  'name is required': 'Введите имя.',
  'login is already taken': 'Этот логин уже занят.',
  'login and password must be provided together': 'Укажите и логин, и пароль.',
  'login must be 3-32 characters long': 'Логин: от 3 до 32 символов.',
  "login may contain only latin letters, digits, '.', '_' and '-'":
      'Логин: только латинские буквы, цифры, точка, _ и -.',
  'password must be at least 6 characters long':
      'Пароль должен быть не короче 6 символов.',
};

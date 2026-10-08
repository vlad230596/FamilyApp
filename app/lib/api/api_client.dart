import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:familyapp/models/child.dart';
import 'package:familyapp/models/chore.dart';
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

  Future<List<Chore>> listChores() async {
    final data = await _get('/api/chores');
    return (data['chores'] as List)
        .map((item) => Chore.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, dynamic>> duties() => _get('/api/duties');
  Future<Map<String, dynamic>> shopping() => _get('/api/shopping');
  Future<void> saveDuty(Map<String, dynamic> data, {int? id}) async {
    await _post(id == null ? '/api/duties' : '/api/duties/$id', data);
  }

  Future<void> completeDuty(int id, Map<String, dynamic> data) async {
    await _post('/api/duties/occurrences/$id/complete', data);
  }

  Future<void> reviewDuty(int id, bool approved, String rating) async {
    await _post('/api/duties/occurrences/$id/review', {
      'approved': approved,
      'rating': rating,
    });
  }

  Future<List<Map<String, dynamic>>> dutyHistory(int id) async {
    final data = await _get('/api/duties/occurrences/$id/history');
    return (data['events'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveAway(String start, String end) async {
    await _post('/api/away-periods', {'start_date': start, 'end_date': end});
  }

  Future<void> cancelAway(int id) async {
    await _post('/api/away-periods/$id/cancel', {});
  }

  Future<Map<String, dynamic>> shoppingList(int id) =>
      _get('/api/shopping?list_id=$id');

  Future<void> saveShoppingList(
    String name, {
    int? id,
    bool main = false,
  }) async {
    await _post('/api/shopping/lists${id == null ? '' : '/$id'}', {
      'name': name,
      'is_main': main,
    });
  }

  Future<void> addShopping(Map<String, dynamic> data) async {
    await _post('/api/shopping', data);
  }

  Future<void> buyShopping(int id, int? days) async {
    await _post('/api/shopping/$id/buy', {'return_in_days': days});
  }

  Future<void> returnShopping(int id, {bool cancel = false}) async {
    await _post(
      '/api/shopping/purchases/$id/${cancel ? 'cancel-return' : 'return'}',
      {},
    );
  }

  Future<void> saveChore(Map<String, dynamic> data, {int? id}) async {
    await _post(id == null ? '/api/chores' : '/api/chores/$id', data);
  }

  Future<void> answerChore(
    int id,
    String date,
    bool answer,
    int revision,
  ) async {
    await _post('/api/chores/$id/answers', {
      'occurrence_date': date,
      'answer': answer,
      'revision': revision,
    });
  }

  Future<List<Map<String, dynamic>>> choreHistory(int id) async {
    final data = await _get('/api/chores/$id/answers');
    return (data['answers'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> choreReminders() async {
    final data = await _get('/api/chores/reminders');
    return (data['reminders'] as List).cast<Map<String, dynamic>>();
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
  'duty not found': 'Дежурство не найдено в этой семье.',
  'duty occurrence not found': 'Дежурство за этот день не найдено.',
  'duty access denied': 'Это дежурство назначено другому участнику.',
  'duty title must be 1-200 characters': 'Название: от 1 до 200 символов.',
  'select duty weekdays': 'Выберите дни недели.',
  'invalid duty assignments': 'Проверьте назначения по дням недели.',
  'new duty cannot start in the past':
      'Новое дежурство можно начать сегодня или позже.',
  'duty start and timezone cannot change':
      'Дата начала и часовой пояс закреплены за дежурством.',
  'duty already submitted':
      'Выполнение уже отправлено или подтверждено. Обновите список.',
  'family is away on this day':
      'В этот день семья отсутствует. Дежурство не учитывается.',
  'children may only submit their own duty':
      'Можно отметить только своё выполнение.',
  'performer is required': 'Выберите исполнителя.',
  'invalid duty rating': 'Выберите оценку выполнения.',
  'duty is not awaiting confirmation':
      'Это выполнение уже рассмотрено. Обновите список.',
  'away end precedes start': 'Конец отсутствия не может быть раньше начала.',
  'away period not found': 'Период уже отменён или не найден.',
  'shopping name must be 1-200 characters':
      'Название покупки: от 1 до 200 символов.',
  'invalid shopping urgency': 'Выберите срочность.',
  'shopping category must be up to 80 characters':
      'Категория: не больше 80 символов.',
  'return days must be 1-3650': 'Возврат: от 1 до 3650 дней.',
  'shopping list name must be 1-80 characters':
      'Название списка: от 1 до 80 символов.',
  'shopping list not found': 'Список покупок не найден. Обновите список.',
  'invalid main shopping list': 'Не удалось выбрать главный список.',
  'shopping item not found':
      'Покупка уже отмечена или не найдена. Обновите список.',
  'purchase not found': 'Запись о покупке не найдена.',
  'only responsible member may answer': 'Ответить может только ответственный.',
  'chore access denied': 'Эта задача назначена другому участнику.',
  'chore not found': 'Задача не найдена в этой семье.',
  'responsible member needs an account':
      'Ответственному нужен доступ в приложение.',
  'responsible member is required': 'Выберите ответственного.',
  'chore title must be 1-200 characters': 'Название: от 1 до 200 символов.',
  'interval_days must be 1-365': 'Интервал: от 1 до 365 дней.',
  'chore changed; refresh before answering':
      'Задача изменена. Обновите список перед ответом.',
  'check is not due':
      'Время этой проверки ещё не наступило или задача приостановлена.',
  'check already answered': 'Ответ на эту проверку уже сохранён.',
  'timezone must be an IANA name':
      'Укажите часовой пояс, например Europe/Moscow.',
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

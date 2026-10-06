import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/config.dart';
import 'package:familyapp/models/child.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/models/restriction.dart';
import 'package:familyapp/models/restriction_type.dart';
import 'package:familyapp/utils/dates.dart';

final apiClientProvider = Provider((ref) => ApiClient(apiBaseUrl));

final familyStoreProvider = NotifierProvider<FamilyStore, FamilyState>(
  FamilyStore.new,
);

class FamilyState {
  const FamilyState({
    this.children = const [],
    this.members = const [],
    this.restrictionTypes = const [],
    this.restrictions = const [],
    this.loading = false,
    this.error,
  });

  final List<Child> children;
  final List<Member> members;
  final List<RestrictionType> restrictionTypes;
  final List<Restriction> restrictions;
  final bool loading;
  final String? error;

  FamilyState copyWith({
    List<Child>? children,
    List<Member>? members,
    List<RestrictionType>? restrictionTypes,
    List<Restriction>? restrictions,
    bool? loading,
    Object? error = _unchanged,
  }) {
    return FamilyState(
      children: children ?? this.children,
      members: members ?? this.members,
      restrictionTypes: restrictionTypes ?? this.restrictionTypes,
      restrictions: restrictions ?? this.restrictions,
      loading: loading ?? this.loading,
      error: error == _unchanged ? this.error : error as String?,
    );
  }

  List<Restriction> restrictionsForDay(DateTime date, {int? childId}) {
    return restrictions.where((item) {
      if (childId != null && item.childId != childId) {
        return false;
      }
      return !dateOnly(date).isBefore(dateOnly(item.startDate)) &&
          !dateOnly(date).isAfter(dateOnly(item.endDate)) &&
          item.status == 'active';
    }).toList();
  }
}

const _unchanged = Object();

class FamilyStore extends Notifier<FamilyState> {
  var _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  FamilyState build() {
    // Rebuilt on sign-in and sign-out, so every session starts fresh.
    Future.microtask(refresh);
    return const FamilyState();
  }

  Future<bool> refresh() async {
    return _run(() async {
      final children = await _api.listChildren();
      final members = await _api.listMembers();
      final restrictionTypes = await _api.listRestrictionTypes();
      final allRestrictions = await _api.listRestrictions();
      final monthRestrictions = await _api.listRestrictionsForRange(
        startOfMonth(_calendarMonth),
        endOfMonth(_calendarMonth),
      );
      state = state.copyWith(
        children: children,
        members: members,
        restrictionTypes: restrictionTypes,
        restrictions: mergeRestrictions(allRestrictions, monthRestrictions),
      );
    });
  }

  Future<bool> loadCalendarMonth(DateTime month) async {
    _calendarMonth = DateTime(month.year, month.month);
    return _run(() async {
      final restrictions = await _api.listRestrictionsForRange(
        startOfMonth(_calendarMonth),
        endOfMonth(_calendarMonth),
      );
      state = state.copyWith(
        restrictions: mergeRestrictions(state.restrictions, restrictions),
      );
    });
  }

  Future<bool> createMember({
    required String name,
    required String icon,
    required String role,
    String? login,
    String? password,
  }) async {
    return _run(() async {
      await _api.createMember(
        name: name,
        icon: icon,
        role: role,
        login: login,
        password: password,
      );
      await _reloadPeople();
    });
  }

  Future<bool> updateMember(int id, String name, String icon) async {
    return _run(() async {
      await _api.updateMember(id, name, icon);
      await refresh();
    });
  }

  Future<bool> setCredentials(int id, String login, String password) async {
    return _run(() async {
      await _api.setCredentials(id, login, password);
      await _reloadPeople();
    });
  }

  Future<void> _reloadPeople() async {
    final children = await _api.listChildren();
    final members = await _api.listMembers();
    state = state.copyWith(children: children, members: members);
  }

  Future<bool> createRestrictionType(String name, String color) async {
    return _run(() async {
      await _api.createRestrictionType(name, color);
      final restrictionTypes = await _api.listRestrictionTypes();
      state = state.copyWith(restrictionTypes: restrictionTypes);
    });
  }

  Future<bool> archiveRestrictionType(int id) async {
    return _run(() async {
      await _api.archiveRestrictionType(id);
      final restrictionTypes = await _api.listRestrictionTypes();
      state = state.copyWith(restrictionTypes: restrictionTypes);
    });
  }

  Future<bool> createRestriction({
    required int childId,
    required DateTime startDate,
    required int durationCount,
    required String durationUnit,
    int? restrictionTypeId,
    String? customTypeName,
    required String color,
    required String reason,
  }) async {
    return _run(() async {
      await _api.createRestriction(
        childId: childId,
        startDate: startDate,
        durationCount: durationCount,
        durationUnit: durationUnit,
        restrictionTypeId: restrictionTypeId,
        customTypeName: customTypeName,
        color: color,
        reason: reason,
      );
      await refresh();
    });
  }

  Future<bool> extendRestriction(int id, DateTime newEndDate) async {
    return _run(() async {
      await _api.extendRestriction(id, newEndDate);
      await refresh();
    });
  }

  Future<bool> cancelRestriction(int id, String note) async {
    return _run(() async {
      await _api.cancelRestriction(id, note);
      await refresh();
    });
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void showError(String message) {
    state = state.copyWith(error: message);
  }

  Future<bool> _run(Future<void> Function() action) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await action();
      return true;
    } catch (exception) {
      state = state.copyWith(error: exception.toString());
      return false;
    } finally {
      state = state.copyWith(loading: false);
    }
  }
}

List<Restriction> mergeRestrictions(
  List<Restriction> first,
  List<Restriction> second,
) {
  final byId = {for (final item in first) item.id: item};
  for (final item in second) {
    byId[item.id] = item;
  }
  final merged = byId.values.toList();
  merged.sort((a, b) => b.endDate.compareTo(a.endDate));
  return merged;
}

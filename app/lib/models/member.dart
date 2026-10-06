class Member {
  Member({
    required this.id,
    required this.name,
    required this.icon,
    required this.role,
    required this.login,
    required this.hasAccount,
  });

  final int id;
  final String name;
  final String icon;
  final String role;
  final String? login;
  final bool hasAccount;

  bool get isParent => role == 'parent';

  factory Member.fromJson(dynamic json) {
    return Member(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'star',
      role: json['role'] as String,
      login: json['login'] as String?,
      hasAccount: json['has_account'] as bool? ?? false,
    );
  }
}

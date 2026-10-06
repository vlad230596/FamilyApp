class Child {
  Child({required this.id, required this.name, required this.icon});

  final int id;
  final String name;
  final String icon;

  factory Child.fromJson(dynamic json) {
    return Child(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'star',
    );
  }
}

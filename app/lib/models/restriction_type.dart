class RestrictionType {
  RestrictionType({
    required this.id,
    required this.name,
    required this.color,
    required this.archived,
  });

  final int id;
  final String name;
  final String color;
  final bool archived;

  factory RestrictionType.fromJson(dynamic json) {
    return RestrictionType(
      id: json['id'] as int,
      name: json['name'] as String,
      color: json['color'] as String,
      archived: json['archived'] as bool? ?? false,
    );
  }
}

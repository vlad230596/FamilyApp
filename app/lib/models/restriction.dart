class Restriction {
  Restriction({
    required this.id,
    required this.childId,
    required this.childName,
    required this.childIcon,
    required this.typeName,
    required this.color,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
  });

  final int id;
  final int childId;
  final String childName;
  final String childIcon;
  final String typeName;
  final String color;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status;

  factory Restriction.fromJson(dynamic json) {
    return Restriction(
      id: json['id'] as int,
      childId: json['child_id'] as int,
      childName: json['child_name'] as String,
      childIcon: json['child_icon'] as String? ?? 'star',
      typeName:
          (json['type_name'] ?? json['reason'] ?? 'Ограничение') as String,
      color: (json['color'] ?? '#607D8B') as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      reason: json['reason'] as String? ?? '',
      status: json['status'] as String,
    );
  }
}

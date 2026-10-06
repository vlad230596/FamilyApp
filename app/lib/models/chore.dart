class Chore {
  Chore.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      title = json['title'] as String,
      responsibleMemberId = json['responsible_member_id'] as int,
      responsibleName = json['responsible_name'] as String,
      startDate = DateTime.parse(json['start_date'] as String),
      intervalDays = json['interval_days'] as int,
      weekdays = List<int>.from(json['weekdays'] as List),
      reminderTime = json['reminder_time'] as String,
      timezone = json['timezone'] as String,
      active = json['active'] as bool,
      revision = json['revision'] as int,
      dueDate = json['due_date'] as String?,
      dueAnswer = json['due_answer'] as bool?,
      nextAt = json['next_at'] as String?;

  final int id;
  final String title;
  final int responsibleMemberId;
  final String responsibleName;
  final DateTime startDate;
  final int intervalDays;
  final List<int> weekdays;
  final String reminderTime;
  final String timezone;
  final bool active;
  final int revision;
  final String? dueDate;
  final bool? dueAnswer;
  final String? nextAt;

  String get scheduleLabel => weekdays.isNotEmpty
      ? weekdays.map((day) => weekdayLabels[day - 1]).join(', ')
      : intervalDays == 1
      ? 'Каждый день'
      : intervalDays == 7
      ? 'Раз в неделю'
      : 'Каждые $intervalDays дн.';
}

const weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

DateTime computeEndDate(DateTime startDate, int count, String unit) {
  final safeCount = count < 1 ? 1 : count;
  return switch (unit) {
    'weeks' => startDate.add(Duration(days: safeCount * 7 - 1)),
    'months' => addMonths(
      startDate,
      safeCount,
    ).subtract(const Duration(days: 1)),
    _ => startDate.add(Duration(days: safeCount - 1)),
  };
}

DateTime addMonths(DateTime value, int months) {
  final monthIndex = value.month - 1 + months;
  final year = value.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, value.day.clamp(1, lastDay));
}

DateTime startOfMonth(DateTime value) => DateTime(value.year, value.month);

DateTime endOfMonth(DateTime value) => DateTime(value.year, value.month + 1, 0);

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool sameDay(DateTime a, DateTime b) => dateOnly(a) == dateOnly(b);

String dateToIso(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String formatDate(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.'
      '${value.year}';
}

String monthTitle(DateTime value) {
  const names = [
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ];
  return '${names[value.month - 1]} ${value.year}';
}

String restrictionCountLabel(int count) {
  final lastTwo = count % 100;
  final last = count % 10;
  final word = lastTwo >= 11 && lastTwo <= 14
      ? 'ограничений'
      : switch (last) {
          1 => 'ограничение',
          2 || 3 || 4 => 'ограничения',
          _ => 'ограничений',
        };
  return '$count $word';
}

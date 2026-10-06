import 'package:flutter/material.dart';

const childIconOptions = [
  'star',
  'pet',
  'bird',
  'butterfly',
  'bug',
  'forest',
  'flower',
  'leaf',
  'eco',
  'park',
  'rocket',
  'sparkles',
  'gamepad',
  'heart',
  'school',
  'bolt',
  'puzzle',
];

IconData childIcon(String icon) {
  return switch (icon) {
    'pet' => Icons.pets,
    'bird' => Icons.flutter_dash,
    'butterfly' => Icons.flutter_dash,
    'bug' => Icons.bug_report,
    'forest' => Icons.forest,
    'flower' => Icons.local_florist,
    'leaf' => Icons.energy_savings_leaf,
    'eco' => Icons.eco,
    'park' => Icons.park,
    'rocket' => Icons.rocket_launch,
    'sparkles' => Icons.auto_awesome,
    'gamepad' => Icons.sports_esports,
    'heart' => Icons.favorite,
    'school' => Icons.school,
    'bolt' => Icons.bolt,
    'puzzle' => Icons.extension,
    _ => Icons.star,
  };
}

String childIconLabel(String icon) {
  return switch (icon) {
    'pet' => 'Лапа',
    'bird' => 'Птица',
    'butterfly' => 'Бабочка',
    'bug' => 'Жук',
    'forest' => 'Лес',
    'flower' => 'Цветок',
    'leaf' => 'Лист',
    'eco' => 'Росток',
    'park' => 'Дерево',
    'rocket' => 'Ракета',
    'sparkles' => 'Искры',
    'gamepad' => 'Игры',
    'heart' => 'Сердце',
    'school' => 'Учеба',
    'bolt' => 'Молния',
    'puzzle' => 'Пазл',
    _ => 'Звезда',
  };
}

import 'package:flutter/material.dart';

const restrictionPalette = [
  '#E53935',
  '#1E88E5',
  '#43A047',
  '#FDD835',
  '#8E24AA',
  '#FB8C00',
  '#00897B',
  '#3949AB',
];

String nextColor(int index) =>
    restrictionPalette[index % restrictionPalette.length];

Color colorFromHex(String value) {
  final cleaned = value.replaceFirst('#', '');
  final parsed = int.tryParse(cleaned, radix: 16) ?? 0x607D8B;
  return Color(0xFF000000 | parsed);
}

import 'package:flutter/material.dart';
import 'package:familyapp/utils/colors.dart';

class ColorDot extends StatelessWidget {
  const ColorDot({required this.color, this.size = 10, super.key});

  final String color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: colorFromHex(color),
        shape: BoxShape.circle,
      ),
    );
  }
}

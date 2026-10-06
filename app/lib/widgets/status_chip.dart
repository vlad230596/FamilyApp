import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'active' => 'Активно',
      'cancelled' => 'Отменено',
      'expired' => 'Истекло',
      _ => status,
    };
    return Chip(label: Text(label));
  }
}

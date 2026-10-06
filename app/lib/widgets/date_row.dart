import 'package:flutter/material.dart';
import 'package:familyapp/utils/dates.dart';

class DateRow extends StatelessWidget {
  const DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(formatDate(value)),
      trailing: const Icon(Icons.calendar_month),
      onTap: onTap,
    );
  }
}

Future<DateTime?> pickDate(BuildContext context, DateTime initialDate) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
  );
}

import 'package:flutter/material.dart';
import 'package:familyapp/models/restriction.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/widgets/date_row.dart';

Future<void> showExtendDialog(
  BuildContext context,
  FamilyStore store,
  Restriction restriction,
) async {
  var newEndDate = restriction.endDate.add(const Duration(days: 1));
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Продлить ограничение'),
        content: DateRow(
          label: 'Новая дата окончания',
          value: newEndDate,
          onTap: () async {
            final picked = await pickDate(context, newEndDate);
            if (picked != null) setState(() => newEndDate = picked);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await store.extendRestriction(
                restriction.id,
                newEndDate,
              );
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Продлить'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCancelDialog(
  BuildContext context,
  FamilyStore store,
  Restriction restriction,
) async {
  final noteController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Отменить ограничение'),
      content: TextField(
        controller: noteController,
        decoration: const InputDecoration(labelText: 'Комментарий'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Нет'),
        ),
        FilledButton(
          onPressed: () async {
            final ok = await store.cancelRestriction(
              restriction.id,
              noteController.text,
            );
            if (ok && context.mounted) Navigator.pop(context);
          },
          child: const Text('Отменить'),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:familyapp/models/restriction_type.dart';
import 'package:familyapp/state/family_store.dart';

Future<void> showArchiveTypeDialog(
  BuildContext context,
  FamilyStore controller,
  RestrictionType type,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Убрать тип в архив?'),
      content: Text(
        '«${type.name}» пропадет из списка для новых ограничений. '
        'Уже созданные ограничения сохранятся.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Нет'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('В архив'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.archiveRestrictionType(type.id);
  }
}

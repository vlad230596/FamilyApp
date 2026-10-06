import 'package:flutter/material.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/utils/colors.dart';
import 'package:familyapp/widgets/color_dot.dart';

Future<void> showRestrictionTypeDialog(
  BuildContext context,
  FamilyState state,
  FamilyStore store,
) async {
  final nameController = TextEditingController();
  var selectedColor = nextColor(state.restrictionTypes.length);
  String? nameError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Тип ограничения'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Название',
                  errorText: nameError,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: restrictionPalette
                    .map(
                      (color) => ChoiceChip(
                        label: ColorDot(color: color, size: 16),
                        selected: selectedColor == color,
                        onSelected: (_) =>
                            setState(() => selectedColor = color),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                setState(() => nameError = 'Введите название');
                return;
              }
              final ok = await store.createRestrictionType(
                nameController.text,
                selectedColor,
              );
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    ),
  );
}

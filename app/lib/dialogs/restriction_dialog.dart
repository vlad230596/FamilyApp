import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/utils/child_icons.dart';
import 'package:familyapp/utils/colors.dart';
import 'package:familyapp/utils/dates.dart';
import 'package:familyapp/widgets/color_dot.dart';
import 'package:familyapp/widgets/date_row.dart';

Future<void> showRestrictionDialog(
  BuildContext context,
  FamilyState state,
  FamilyStore store,
) async {
  if (state.children.isEmpty) {
    store.showError('Сначала добавьте ребенка в настройках.');
    return;
  }

  var selectedChildId = state.children.first.id;
  var useCustomType = state.restrictionTypes.isEmpty;
  int? selectedTypeId = state.restrictionTypes.isEmpty
      ? null
      : state.restrictionTypes.first.id;
  var selectedColor = nextColor(state.restrictionTypes.length);
  var startDate = DateTime.now();
  var durationCount = 1;
  var durationUnit = 'days';
  final customTypeController = TextEditingController();
  final reasonController = TextEditingController();
  String? typeError;
  String? durationError;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final endDate = computeEndDate(startDate, durationCount, durationUnit);
        return AlertDialog(
          title: const Text('Новое ограничение'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedChildId,
                  decoration: const InputDecoration(labelText: 'Ребенок'),
                  items: state.children
                      .map(
                        (child) => DropdownMenuItem(
                          value: child.id,
                          child: Row(
                            children: [
                              Icon(childIcon(child.icon), size: 18),
                              const SizedBox(width: 8),
                              Text(child.name),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => selectedChildId = value ?? selectedChildId,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.bookmark),
                      label: Text('Тип'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.edit),
                      label: Text('Разовое'),
                    ),
                  ],
                  selected: {useCustomType},
                  onSelectionChanged: (value) => setState(() {
                    useCustomType = value.first;
                    typeError = null;
                  }),
                ),
                const SizedBox(height: 8),
                if (!useCustomType)
                  DropdownButtonFormField<int>(
                    initialValue: selectedTypeId,
                    decoration: InputDecoration(
                      labelText: 'Тип ограничения',
                      errorText: typeError,
                    ),
                    items: state.restrictionTypes
                        .map(
                          (type) => DropdownMenuItem(
                            value: type.id,
                            child: Row(
                              children: [
                                ColorDot(color: type.color),
                                const SizedBox(width: 8),
                                Text(type.name),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedTypeId = value),
                  )
                else ...[
                  TextField(
                    controller: customTypeController,
                    decoration: InputDecoration(
                      labelText: 'Название',
                      errorText: typeError,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(labelText: 'Комментарий'),
                ),
                const SizedBox(height: 12),
                DateRow(
                  label: 'Начало',
                  value: startDate,
                  onTap: () async {
                    final picked = await pickDate(context, startDate);
                    if (picked != null) setState(() => startDate = picked);
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: '$durationCount',
                        decoration: InputDecoration(
                          labelText: 'Срок',
                          errorText: durationError,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) => setState(() {
                          durationCount = int.tryParse(value) ?? 0;
                          durationError = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: durationUnit,
                        decoration: const InputDecoration(labelText: 'Единица'),
                        items: const [
                          DropdownMenuItem(value: 'days', child: Text('дней')),
                          DropdownMenuItem(
                            value: 'weeks',
                            child: Text('недель'),
                          ),
                          DropdownMenuItem(
                            value: 'months',
                            child: Text('месяцев'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => durationUnit = value ?? durationUnit,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Окончание: ${formatDate(endDate)}'),
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
                var valid = true;
                setState(() {
                  typeError = null;
                  durationError = null;
                  if (durationCount < 1) {
                    durationError = 'Минимум 1';
                    valid = false;
                  }
                  if (useCustomType &&
                      customTypeController.text.trim().isEmpty) {
                    typeError = 'Введите название';
                    valid = false;
                  }
                  if (!useCustomType && selectedTypeId == null) {
                    typeError = 'Выберите тип';
                    valid = false;
                  }
                });
                if (!valid) return;

                final type = state.restrictionTypes
                    .where((item) => item.id == selectedTypeId)
                    .firstOrNull;
                final ok = await store.createRestriction(
                  childId: selectedChildId,
                  startDate: startDate,
                  durationCount: durationCount,
                  durationUnit: durationUnit,
                  restrictionTypeId: useCustomType ? null : selectedTypeId,
                  customTypeName: useCustomType
                      ? customTypeController.text.trim()
                      : null,
                  color: useCustomType
                      ? selectedColor
                      : type?.color ?? selectedColor,
                  reason: reasonController.text,
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
              child: const Text('Создать'),
            ),
          ],
        );
      },
    ),
  );
}

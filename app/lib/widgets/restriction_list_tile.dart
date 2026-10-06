import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/dialogs/restriction_action_dialogs.dart';
import 'package:familyapp/models/restriction.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/utils/child_icons.dart';
import 'package:familyapp/utils/dates.dart';
import 'package:familyapp/widgets/color_dot.dart';
import 'package:familyapp/widgets/status_chip.dart';

class RestrictionListTile extends ConsumerWidget {
  const RestrictionListTile({
    required this.restriction,
    required this.controller,
    super.key,
  });

  final Restriction restriction;
  final FamilyStore controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = restriction.status == 'active';
    final canManage = ref.watch(authStoreProvider).isParent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ColorDot(color: restriction.color, size: 14),
                const SizedBox(width: 8),
                Icon(childIcon(restriction.childIcon), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    restriction.typeName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusChip(status: restriction.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(restriction.childName),
            if (restriction.reason.isNotEmpty) Text(restriction.reason),
            Text(
              '${formatDate(restriction.startDate)} - ${formatDate(restriction.endDate)}',
            ),
            if (active && canManage) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        showExtendDialog(context, controller, restriction),
                    icon: const Icon(Icons.update),
                    label: const Text('Продлить'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        showCancelDialog(context, controller, restriction),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Отменить'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

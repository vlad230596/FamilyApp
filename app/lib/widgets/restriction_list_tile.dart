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
import 'package:familyapp/theme/solar_theme.dart';

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
            Text(
              '${formatDate(restriction.startDate)} - ${formatDate(restriction.endDate)}',
            ),
            const SizedBox(height: 12),
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: active ? SolarColors.coral : SolarColors.border,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 8),
            if (active)
              Text(
                'Снова можно ${formatDate(restriction.endDate.add(const Duration(days: 1)))}',
                style: const TextStyle(
                  color: SolarColors.coralText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Подробнее'),
              children: [
                if (restriction.reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(restriction.reason),
                  ),
                if (active && canManage)
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
            ),
          ],
        ),
      ),
    );
  }
}

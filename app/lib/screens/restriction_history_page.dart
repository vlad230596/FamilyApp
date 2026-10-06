import 'package:flutter/material.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/widgets/empty_state.dart';
import 'package:familyapp/widgets/restriction_list_tile.dart';

class RestrictionHistoryPage extends StatelessWidget {
  const RestrictionHistoryPage({
    required this.state,
    required this.controller,
    super.key,
  });

  final FamilyState state;
  final FamilyStore controller;

  @override
  Widget build(BuildContext context) {
    if (state.restrictions.isEmpty) {
      return const EmptyState(
        icon: Icons.event_note,
        title: 'Ограничений пока нет',
        message: 'Здесь появятся активные, прошедшие и отмененные ограничения.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: state.restrictions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => RestrictionListTile(
        restriction: state.restrictions[index],
        controller: controller,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:familyapp/models/child.dart';
import 'package:familyapp/models/restriction.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/utils/child_icons.dart';
import 'package:familyapp/utils/colors.dart';
import 'package:familyapp/utils/dates.dart';
import 'package:familyapp/utils/labels.dart';
import 'package:familyapp/widgets/color_dot.dart';
import 'package:familyapp/widgets/empty_state.dart';
import 'package:familyapp/widgets/restriction_list_tile.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    required this.state,
    required this.controller,
    this.showChildFilter = true,
    super.key,
  });

  final FamilyState state;
  final FamilyStore controller;
  final bool showChildFilter;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selectedDate;
  int? _selectedChildId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final restrictions = widget.state.restrictionsForDay(
      _selectedDate,
      childId: _selectedChildId,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: [
        if (widget.showChildFilter)
          CalendarChildFilter(
            children: widget.state.children,
            selectedChildId: _selectedChildId,
            onSelected: (childId) => setState(() => _selectedChildId = childId),
          ),
        Row(
          children: [
            IconButton(
              tooltip: 'Предыдущий месяц',
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: Text(
                  monthTitle(_month),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Следующий месяц',
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        MonthGrid(
          month: _month,
          selectedDate: _selectedDate,
          state: widget.state,
          childId: _selectedChildId,
          onSelected: (date) => setState(() => _selectedDate = date),
        ),
        const SizedBox(height: 12),
        SelectedDaySummary(
          date: _selectedDate,
          count: restrictions.length,
          filtered: _selectedChildId != null,
        ),
        const SizedBox(height: 8),
        if (restrictions.isEmpty)
          EmptyInline(
            message: _selectedChildId == null
                ? 'На этот день ограничений нет.'
                : 'У выбранного ребенка на этот день ограничений нет.',
          )
        else
          ...restrictions.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RestrictionListTile(
                restriction: item,
                controller: widget.controller,
              ),
            ),
          ),
        if (widget.state.restrictionTypes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.state.restrictionTypes
                .map(
                  (type) => Chip(
                    avatar: ColorDot(color: type.color),
                    label: Text(type.name),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    setState(() {
      _month = next;
      _selectedDate = DateTime(next.year, next.month, 1);
    });
    widget.controller.loadCalendarMonth(next);
  }
}

class MonthGrid extends StatelessWidget {
  const MonthGrid({
    required this.month,
    required this.selectedDate,
    required this.state,
    required this.childId,
    required this.onSelected,
    super.key,
  });

  final DateTime month;
  final DateTime selectedDate;
  final FamilyState state;
  final int? childId;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final leading = first.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = leading + days;
    final totalCells = cells + ((7 - cells % 7) % 7);
    final compact = MediaQuery.sizeOf(context).height < 720;

    return Column(
      children: [
        const Row(
          children: [
            DayHeader('Пн'),
            DayHeader('Вт'),
            DayHeader('Ср'),
            DayHeader('Чт'),
            DayHeader('Пт'),
            DayHeader('Сб'),
            DayHeader('Вс'),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalCells,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: compact ? 2 : 3,
            crossAxisSpacing: 3,
            mainAxisExtent: compact ? 36 : 44,
          ),
          itemBuilder: (context, index) {
            final dayNumber = index - leading + 1;
            if (dayNumber < 1 || dayNumber > days) {
              return const SizedBox.shrink();
            }
            final date = DateTime(month.year, month.month, dayNumber);
            final restrictions = state.restrictionsForDay(
              date,
              childId: childId,
            );
            final selected = sameDay(date, selectedDate);
            final today = sameDay(date, DateTime.now());
            final past = dateOnly(date).isBefore(dateOnly(DateTime.now()));
            final colorScheme = Theme.of(context).colorScheme;
            final borderColor = selected
                ? colorScheme.primary
                : today
                ? colorScheme.tertiary
                : past
                ? colorScheme.outlineVariant.withValues(alpha: 0.45)
                : colorScheme.outlineVariant;
            final backgroundColor = selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                : today
                ? colorScheme.tertiaryContainer.withValues(alpha: 0.35)
                : past
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
                : colorScheme.surface;
            final textColor = past && !selected && !today
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                : colorScheme.onSurface;
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onSelected(date),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: borderColor,
                    width: selected || today ? 1.6 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dayNumber',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: textColor,
                        fontWeight: today ? FontWeight.w700 : null,
                      ),
                    ),
                    if (!compact) const SizedBox(height: 2),
                    SizedBox(
                      height: 16,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 1,
                        runSpacing: 1,
                        children: restrictions
                            .take(4)
                            .map(
                              (item) => ChildRestrictionMarker(
                                restriction: item,
                                muted: past && !today && !selected,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class CalendarChildFilter extends StatelessWidget {
  const CalendarChildFilter({
    required this.children,
    required this.selectedChildId,
    required this.onSelected,
    super.key,
  });

  final List<Child> children;
  final int? selectedChildId;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: const Icon(Icons.groups, size: 18),
              label: const Text('Все'),
              selected: selectedChildId == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(childIcon(child.icon), size: 18),
                label: Text(child.name),
                selected: selectedChildId == child.id,
                onSelected: (_) => onSelected(child.id),
              ),
            ),
        ],
      ),
    );
  }
}

class SelectedDaySummary extends StatelessWidget {
  const SelectedDaySummary({
    required this.date,
    required this.count,
    required this.filtered,
    super.key,
  });

  final DateTime date;
  final int count;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final label = restrictionCountLabel(count);
    final prefix = sameDay(date, DateTime.now()) ? 'Сегодня' : formatDate(date);
    final suffix = filtered ? ' у выбранного ребенка' : '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.event_available),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$prefix: $label$suffix',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChildRestrictionMarker extends StatelessWidget {
  const ChildRestrictionMarker({
    required this.restriction,
    required this.muted,
    super.key,
  });

  final Restriction restriction;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
        : colorFromHex(restriction.color);
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: color.withValues(alpha: muted ? 0.12 : 0.18),
        shape: BoxShape.circle,
      ),
      child: Icon(childIcon(restriction.childIcon), size: 11, color: color),
    );
  }
}

class DayHeader extends StatelessWidget {
  const DayHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

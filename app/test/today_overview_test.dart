import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:familyapp/models/child.dart';
import 'package:familyapp/models/restriction.dart';
import 'package:familyapp/screens/calendar_page.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/widgets/color_dot.dart';

void main() {
  testWidgets(
    'today overview shows multiple restriction colors and unrestricted children',
    (tester) async {
      final today = DateTime.now();
      Restriction restriction(
        int id,
        String name,
        String color, {
        String status = 'active',
      }) => Restriction(
        id: id,
        childId: 1,
        childName: 'Миша',
        childIcon: 'star',
        typeName: name,
        color: color,
        startDate: today.subtract(const Duration(days: 1)),
        endDate: today.add(const Duration(days: 1)),
        reason: '',
        status: status,
      );
      final state = FamilyState(
        children: [
          Child(id: 1, name: 'Миша', icon: 'star'),
          Child(id: 2, name: 'Маша', icon: 'star'),
        ],
        restrictions: [
          restriction(1, 'Телефон', '#FF0000'),
          restriction(2, 'Игры', '#0000FF'),
          restriction(3, 'Отменённое', '#FFFF00', status: 'cancelled'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TodayRestrictionsOverview(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ColorDot), findsNWidgets(2));
      expect(find.text('Сегодня ограничений нет'), findsOneWidget);
      expect(find.textContaining('Отменённое'), findsNothing);
    },
  );
}

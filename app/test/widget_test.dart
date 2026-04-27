import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:familyapp/main.dart';

void main() {
  testWidgets('shows FamilyApp tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(FakeApiClient())],
        child: const FamilyApp(),
      ),
    );
    await tester.pump();

    expect(find.text('FamilyApp'), findsOneWidget);
    expect(find.text('Дети'), findsOneWidget);
    expect(find.text('Ограничения'), findsOneWidget);
  });
}

class FakeApiClient extends ApiClient {
  FakeApiClient() : super('http://127.0.0.1:5055');

  @override
  Future<List<Child>> listChildren() async => [];

  @override
  Future<List<Restriction>> listRestrictions() async => [];
}

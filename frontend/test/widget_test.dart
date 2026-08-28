import 'package:flutter_test/flutter_test.dart';

import 'package:team_chai_and_code/main.dart';

void main() {
  testWidgets('shows the app name', (WidgetTester tester) async {
    await tester.pumpWidget(const TeamChaiAndCodeApp());

    expect(find.text('teamChaiAndCode'), findsOneWidget);
  });
}

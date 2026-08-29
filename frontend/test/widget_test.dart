import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:team_chai_and_code/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the chat welcome state', (WidgetTester tester) async {
    await tester.pumpWidget(const TeamChaiAndCodeApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('What can I do for you today?'), findsOneWidget);
  });
}

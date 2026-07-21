import 'package:flutter_test/flutter_test.dart';

import 'package:randomselector/app.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RandomSelectorApp());
    // Verify the app renders without crashing
    expect(find.text('题库抽题器'), findsOneWidget);
  });
}

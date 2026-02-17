import 'package:flutter_test/flutter_test.dart';

import 'package:audiobook_validator/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AudiobookValidatorApp());

    // Verify basic app structure
    expect(find.text('Audiobook\nValidator'), findsOneWidget);
  });
}

// Basic Flutter widget test for Smart Cane app

import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_1/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartCaneApp());

    // Verify that the app title is present
    expect(find.text('স্মার্ট ক্যান'), findsOneWidget);
  });
}

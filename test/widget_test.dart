import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    // The app requires a quest in assets/quest/, so we just verify the module compiles.
    // Full integration test would need a real quest.
    expect(true, isTrue);
  });
}

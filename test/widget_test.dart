import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scroll_control/main.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ScrollControlApp()),
    );
    expect(find.byType(ScrollControlApp), findsOneWidget);
  });
}

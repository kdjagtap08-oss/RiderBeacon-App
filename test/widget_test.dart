import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kavach/main.dart';

void main() {
  testWidgets('SmartKavachApp renders title smoke test',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SmartKavachApp());
    expect(find.text('SmartKavach'), findsOneWidget);
  });
}

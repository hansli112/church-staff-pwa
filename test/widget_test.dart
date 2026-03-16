import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke test renders text', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Church Staff PWA'),
          ),
        ),
      ),
    );

    expect(find.text('Church Staff PWA'), findsOneWidget);
  });
}

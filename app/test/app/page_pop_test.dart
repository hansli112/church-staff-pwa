import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// A pushed page that the phone pops twice, as some Android phones' back
// does: Crashlytics had 「Bad state: Future already completed」 from
// go_router (flutter/flutter#187326). The second pop goes by quietly.
void main() {
  testWidgets('a pushed page completes once, however many times it is popped', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    addTearDown(router.dispose);
    final opened = Completer<Object?>();
    final page = ImperativeRouteMatch(
      pageKey: const ValueKey('page'),
      matches: router.configuration.findMatch(Uri.parse('/')),
      completer: opened,
    );

    page.complete('first');
    page.complete('second');

    expect(await opened.future, 'first');
  });
}

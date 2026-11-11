import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/church/church_logo.dart';

import '../support/harness.dart';

void main() {
  /// Where the church's name starts in the home title.
  Future<double> nameStart(WidgetTester tester, Church church) async {
    await pumpWidgetInApp(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: ChurchTitle(church: church),
      ),
    );
    return tester.getTopLeft(find.text(church.name)).dx;
  }

  testWidgets('the name does not move when the logo comes: its room is kept while it is looked up and loaded', (
    tester,
  ) async {
    const name = '竹圍靈糧福音中心';
    final none = await nameStart(tester, const Church(id: 'zw', name: name));
    final lookingUp = await nameStart(tester, const Church(id: 'zw', name: name, hasLogo: true));
    // Tests have no network: the image never arrives, as on a slow one.
    final loading = await nameStart(
      tester,
      const Church(id: 'zw', name: name, logoUrl: 'https://example.com/logo.png'),
    );
    expect(lookingUp, greaterThan(none + 32));
    expect(loading, lookingUp);
  });
}

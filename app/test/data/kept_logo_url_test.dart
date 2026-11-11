import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/cache/kept_logo_url.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test("a logo's URL is looked up once per version, then kept on the device", () async {
    SharedPreferences.setMockInitialValues({});
    var lookups = 0;
    Future<String> url(String version) => keptLogoUrl(
      SharedPreferences.getInstance(),
      churchId: 'zw',
      version: version,
      lookUp: () async => 'https://storage/zw/logo.png?v=$version&n=${++lookups}',
    );
    expect(await url('1'), 'https://storage/zw/logo.png?v=1&n=1');
    await pumpEventQueue();
    expect(await url('1'), 'https://storage/zw/logo.png?v=1&n=1', reason: 'the next opening of the app');
    expect(lookups, 1);
    expect(await url('2'), 'https://storage/zw/logo.png?v=2&n=2', reason: 'a new logo');
    expect(lookups, 2);
  });

  test("another church's kept URL is not this one's", () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferences.getInstance();
    await keptLogoUrl(prefs, churchId: 'a', version: '1', lookUp: () async => 'https://a');
    await pumpEventQueue();
    expect(await keptLogoUrl(prefs, churchId: 'b', version: '1', lookUp: () async => 'https://b'), 'https://b');
  });

  test('with the device unable to keep anything, it is looked up each time', () async {
    var lookups = 0;
    for (var i = 0; i < 2; i++) {
      await keptLogoUrl(
        Future<SharedPreferences>.error(StateError('no prefs')),
        churchId: 'zw',
        version: '1',
        lookUp: () async => 'https://${++lookups}',
      );
    }
    expect(lookups, 2);
  });
}

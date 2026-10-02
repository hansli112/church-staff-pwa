import 'package:flutter_test/flutter_test.dart';
import 'package:martha/router.dart';
import 'package:martha/state/providers.dart';

String? go(AppStage stage, String location) => redirectFor(stage, Uri.parse(location));

void main() {
  test('while loading, waits and remembers where it was going', () {
    expect(go(AppStage.loading, '/join/ABC'), '/loading?from=%2Fjoin%2FABC');
    expect(go(AppStage.loading, '/loading?from=%2Fjoin%2FABC'), isNull);
  });

  test('signed out goes to login, keeping an invite link', () {
    expect(
      go(AppStage.signedOut, '/loading?from=%2Fjoin%2FABC'),
      '/login?from=%2Fjoin%2FABC',
    );
    expect(go(AppStage.signedOut, '/join/ABC'), '/login?from=%2Fjoin%2FABC');
    expect(go(AppStage.signedOut, '/home'), '/login?from=%2Fhome');
    expect(go(AppStage.signedOut, '/login'), isNull);
  });

  test('after sign-in, an invite link resumes', () {
    expect(go(AppStage.noChurch, '/login?from=%2Fjoin%2FABC'), '/join/ABC');
    expect(go(AppStage.ready, '/login?from=%2Fjoin%2FABC'), '/join/ABC');
  });

  test('no church: welcome, unless joining or deleting the account', () {
    expect(go(AppStage.noChurch, '/home'), '/welcome');
    expect(go(AppStage.noChurch, '/login'), '/welcome');
    expect(go(AppStage.noChurch, '/welcome/create'), isNull);
    expect(go(AppStage.noChurch, '/account'), isNull);
    expect(go(AppStage.noChurch, '/login?from=%2Fhome'), '/welcome');
  });

  test('a closed church shows the closed page', () {
    expect(go(AppStage.churchClosed, '/rosters'), '/closed');
    expect(go(AppStage.churchClosed, '/closed'), isNull);
  });

  test('ready: leaves waiting pages for the original target or home', () {
    expect(go(AppStage.ready, '/loading'), '/home');
    expect(
      go(AppStage.ready, '/loading?from=%2Fdev%2Fcomponents'),
      '/dev/components',
    );
    expect(go(AppStage.ready, '/welcome'), '/home');
    expect(go(AppStage.ready, '/rosters'), isNull);
  });
}

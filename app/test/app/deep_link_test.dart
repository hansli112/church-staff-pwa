import 'package:flutter_test/flutter_test.dart';
import 'package:martha/deep_link.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';

const loading = AppStage.loading;
const signedOut = AppStage.signedOut;
const noChurch = AppStage.noChurch;
const closed = AppStage.churchClosed;
const ready = AppStage.ready;

/// Signed in, I am in grace and hope; `other` is someone else's church.
final mine = [
  for (final id in ['grace', 'hope'])
    Membership(
      churchId: id,
      member: const Member(uid: 'me', name: '王小明'),
    ),
];

LinkTarget go(AppStage stage, String location) => resolveLink(
  stage,
  stage == signedOut || stage == noChurch ? const [] : mine,
  Uri.parse(location),
);

const LinkTarget stay = (location: null, church: null);

LinkTarget to(String location, {String? church}) => (location: location, church: church);

String e(String location) => Uri.encodeComponent(location);

/// Each row: at this stage, this link goes there.
void table(String name, List<(AppStage, String, LinkTarget)> rows) {
  test(name, () {
    for (final (stage, link, want) in rows) {
      expect(go(stage, link), want, reason: '${stage.name} $link');
    }
  });
}

/// Follows [link] through [stages] as the router does: a new stage runs the
/// redirect again where it is, and a redirect is redirected again until one
/// stays. Where it ends, and the church switched to last.
({String at, String? church}) journey(List<AppStage> stages, String link) {
  var at = link;
  String? church;
  for (final stage in stages) {
    for (var hops = 0; ; hops++) {
      expect(hops, lessThan(5), reason: 'redirect loop at $at');
      final next = go(stage, at);
      church = next.church ?? church;
      if (next.location == null) break;
      at = next.location!;
    }
  }
  return (at: at, church: church);
}

const invite = '/c/grace/join/ABC';

void main() {
  table('while loading, waits and remembers where it was going', [
    (loading, invite, to('/loading?from=%2Fc%2Fgrace%2Fjoin%2FABC')),
    (loading, '/loading?from=%2Fc%2Fgrace%2Fjoin%2FABC', stay),
    (loading, '/rosters', to('/loading?from=%2Frosters')),
    (loading, '/c/other', to('/loading?from=%2Fc%2Fother')),
  ]);

  table('signed out goes to login, keeping the page asked for', [
    (signedOut, '/loading?from=%2Fc%2Fgrace%2Fjoin%2FABC', to('/login?from=%2Fc%2Fgrace%2Fjoin%2FABC')),
    (signedOut, invite, to('/login?from=%2Fc%2Fgrace%2Fjoin%2FABC')),
    (signedOut, '/home', to('/login?from=%2Fhome')),
    (signedOut, '/c/hope?to=%2Fme', to('/login?from=${e('/c/hope?to=%2Fme')}')),
    (signedOut, '/login', stay),
    (signedOut, '/loading', to('/login')),
  ]);

  table('after sign-in, the page asked for resumes', [
    (noChurch, '/login?from=%2Fc%2Fgrace%2Fjoin%2FABC', to(invite)),
    (ready, '/login?from=%2Fc%2Fgrace%2Fjoin%2FABC', to(invite)),
    (closed, '/loading?from=%2Fc%2Fgrace%2Fjoin%2FABC', to(invite)),
    (ready, '/loading?from=%2Fdev%2Fcomponents', to('/dev/components')),
    (ready, '/login?from=%2Frosters', to('/rosters')),
    // Where the stage allows it: without a church, not the church's pages.
    (noChurch, '/login?from=%2Fhome', to('/welcome')),
    (closed, '/login?from=%2Frosters', to('/closed')),
    // A notification tapped while signed out: its church, at its page.
    (ready, '/login?from=${e('/c/hope?to=%2Fme')}', to('/me', church: 'hope')),
  ]);

  table('no church: welcome, unless joining or deleting the account', [
    (noChurch, '/home', to('/welcome')),
    (noChurch, '/login', to('/welcome')),
    (noChurch, '/welcome/create', stay),
    (noChurch, '/account', stay),
    (noChurch, invite, stay),
  ]);

  table('a closed church shows the closed page', [
    (closed, '/rosters', to('/closed')),
    (closed, '/closed', stay),
    (closed, '/account', stay),
    (closed, '/welcome/join', stay),
    (closed, invite, stay),
  ]);

  table('ready: leaves waiting pages for home', [
    (ready, '/loading', to('/home')),
    (ready, '/login', to('/home')),
    (ready, '/welcome', to('/home')),
    (ready, '/closed', to('/home')),
    (ready, '/rosters', stay),
    (ready, invite, stay),
  ]);

  table('a church URL of my church switches to it, at its notification page', [
    (ready, '/c/hope', to('/home', church: 'hope')),
    (ready, '/c/hope?to=%2Fme', to('/me', church: 'hope')),
    (ready, '/c/hope?to=%2Frosters%2Fworship%2F2026-10-04', to('/rosters/worship/2026-10-04', church: 'hope')),
    (ready, '/c/grace', to('/home', church: 'grace')),
    (closed, '/c/hope', to('/home', church: 'hope')),
    // Memberships known, the church itself still loading.
    (loading, '/c/hope?to=%2Fme', to('/me', church: 'hope')),
  ]);

  table('a church URL of another church shows it, at every stage with an account', [
    (signedOut, '/c/other', to('/login?from=%2Fc%2Fother')),
    (noChurch, '/c/other', stay),
    (closed, '/c/other', stay),
    (ready, '/c/other', stay),
    (ready, '/c/other?to=%2Fme', stay),
    (noChurch, '/login?from=%2Fc%2Fother', to('/c/other')),
  ]);

  table('an unknown page: the stage decides, ready shows not found', [
    (loading, '/nope', to('/loading?from=%2Fnope')),
    (signedOut, '/nope', to('/login?from=%2Fnope')),
    (noChurch, '/nope', to('/welcome')),
    (closed, '/nope', to('/closed')),
    (ready, '/nope', stay),
    (ready, '/c', stay),
  ]);

  group('from and to never lead to another site', () {
    const bad = ['//evil.com', 'https://evil.com', r'/\evil.com', '/\t/evil.com', 'evil.com', 'javascript:alert(1)'];

    table('from', [
      for (final b in bad) ...[
        (signedOut, '/loading?from=${e(b)}', to('/login')),
        (loading, '/login?from=${e(b)}', to('/loading')),
        (noChurch, '/login?from=${e(b)}', to('/welcome')),
        (closed, '/login?from=${e(b)}', to('/closed')),
        (ready, '/login?from=${e(b)}', to('/home')),
      ],
    ]);

    table('to', [
      for (final b in bad) (ready, '/c/hope?to=${e(b)}', to('/home', church: 'hope')),
    ]);

    test('through sign-in, at every stage it can end in', () {
      for (final b in bad) {
        for (final link in ['/login?from=${e(b)}', '/c/hope?to=${e(b)}', '/login?from=${e('/c/hope?to=${e(b)}')}']) {
          for (final end in [noChurch, closed, ready]) {
            final landed = journey([loading, signedOut, loading, end], link);
            // A `to` left on another church's page is never read.
            expect(Uri.parse(landed.at).path, isNot(contains('evil')), reason: '$link → ${end.name}');
            expect(appLocation(landed.at), landed.at);
          }
        }
      }
    });
  });

  test('a notification tapped while signed out lands on its page in its church', () {
    expect(journey([signedOut, loading, ready], '/c/hope?to=%2Fme'), (at: '/me', church: 'hope'));
    expect(journey([loading, signedOut, loading, ready], invite), (at: invite, church: null));
  });

  test('appLocation keeps only pages of this app', () {
    for (final ok in ['/home', '/c/hope?to=%2Fme', '/me/members/u1']) {
      expect(appLocation(ok), ok);
    }
    for (final no in [null, '', 'home', '//evil.com', 'https://evil.com', r'/\evil.com', '/\n/evil.com']) {
      expect(appLocation(no), isNull, reason: '$no');
    }
  });

  test('churchUrlId reads only /c/ID', () {
    expect(churchUrlId(Uri.parse('/c/grace')), 'grace');
    expect(churchUrlId(Uri.parse('/c/grace?x=1')), 'grace');
    expect(churchUrlId(Uri.parse('/c/grace/join/ABC')), isNull);
    expect(churchUrlId(Uri.parse('/c')), isNull);
    expect(churchUrlId(Uri.parse('/home')), isNull);
  });
}

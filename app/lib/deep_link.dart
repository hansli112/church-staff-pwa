import 'domain/models.dart';
import 'state/providers.dart';

/// Where a link takes someone: the [location] to go to (null stays where
/// the link points), and the [church] to switch to first.
typedef LinkTarget = ({String? location, String? church});

const LinkTarget _stay = (location: null, church: null);

LinkTarget _go(String location) => (location: location, church: null);

/// Where someone opening [uri] goes, given the app [stage] and the churches
/// they are in. Every way into a page comes through here: a typed or shared
/// URL, an invite link, a church URL (`/c/ID`, also a home-screen shortcut
/// and a notification's link with `?to=`), and the page someone was going
/// to before signing in (`from`).
///
/// Pure: the router applies it, and switches church when asked.
LinkTarget resolveLink(AppStage stage, List<Membership> memberships, Uri uri) {
  // A church URL of one of my churches opens that church, at `?to=` if
  // given (a notification's page). Someone else sees the church's page.
  // So does an invite to a church I am already in: nothing to join.
  final cid = churchUrlId(uri) ?? inviteChurchId(uri);
  if (cid != null && memberships.any((m) => m.churchId == cid)) {
    return (location: appLocation(uri.queryParameters['to']) ?? '/home', church: cid);
  }

  final path = uri.path;
  bool at(String prefix) => path == prefix || path.startsWith('$prefix/');
  final from = appLocation(uri.queryParameters['from']);

  /// Away from the page asked for (an invite link, a deep link), which goes
  /// along in `from` so they land there once signed in.
  LinkTarget away(String target) {
    final keep = from ?? (at('/loading') || at('/login') ? null : appLocation(uri.toString()));
    return _go(keep == null ? target : '$target?from=${Uri.encodeComponent(keep)}');
  }

  /// Leaves a waiting page for [from], wherever this stage sends that.
  LinkTarget resume(String fallback) {
    if (from == null) return _go(fallback);
    final again = resolveLink(stage, memberships, Uri.parse(from));
    return again.location == null ? _go(from) : again;
  }

  switch (stage) {
    case AppStage.loading:
      return at('/loading') ? _stay : away('/loading');
    case AppStage.signedOut:
      return at('/login') ? _stay : away('/login');
    case AppStage.noChurch:
      // 加入主畫面 comes right after joining, maybe before the church has.
      if (at('/welcome') || at('/c') || at('/account') || at('/dev') || at('/add-to-home')) return _stay;
      if (at('/loading') || at('/login')) return resume('/welcome');
      return _go('/welcome');
    case AppStage.churchClosed:
      if (at('/closed') || at('/c') || at('/account') || at('/welcome') || at('/dev')) {
        return _stay;
      }
      if (at('/loading') || at('/login')) return resume('/closed');
      return _go('/closed');
    case AppStage.ready:
      // Joining or starting another church, from 切換教會: only the
      // welcome page itself is for someone in no church.
      if (at('/welcome') && path != '/welcome') return _stay;
      if (at('/loading') || at('/login') || at('/welcome') || at('/closed')) {
        return resume('/home');
      }
      return _stay;
  }
}

/// The church ID of a church URL (`/c/ID`), or null.
String? churchUrlId(Uri uri) {
  final parts = uri.pathSegments;
  return parts.length == 2 && parts[0] == 'c' && parts[1].isNotEmpty ? parts[1] : null;
}

/// The church ID of an invite link (`/c/ID/join/CODE`), or null.
String? inviteChurchId(Uri uri) {
  final parts = uri.pathSegments;
  return parts.length == 4 && parts[0] == 'c' && parts[1].isNotEmpty && parts[2] == 'join' ? parts[1] : null;
}

/// [link] if it is a page of this app: a path from the root, no scheme, no
/// host. Null for anything else, so `from`, `to` and a notification's link
/// never lead to another site.
String? appLocation(String? link) {
  if (link == null || !link.startsWith('/') || link.startsWith('//')) return null;
  // Browsers read `\` as `/` and drop tabs and newlines: `/\host` and
  // `/\t/host` are `//host` to them.
  if (link.contains(r'\') || link.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return null;
  return link;
}

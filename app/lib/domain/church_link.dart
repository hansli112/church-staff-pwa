import 'models.dart';

/// A sourced link is shown only when valid, dated the church's today;
/// failures never replace it with old content or the fixed link.
({String title, String body, String url})? shownChurchLink(
  ChurchLink link,
  LinkContent? content,
  DateTime now,
  ChurchTimeZone timeZone,
) {
  if (link.source == null) return (title: link.title, body: link.body, url: link.url);
  final fetched = content?.fetchedAt;
  final url = content?.link;
  final today = timeZone.today(now).key;
  final fresh =
      content != null &&
      content.source == link.source &&
      content.error == null &&
      content.date == today &&
      content.title.isNotEmpty &&
      url != null &&
      ChurchLink.validUrl(url) &&
      // The server's clock: a phone a little slow must not hide it.
      fetched != null &&
      timeZone.today(fetched).key == today;
  if (!fresh) return null;
  return (title: content.title, body: content.body, url: url);
}

/// `HH:MM` of [minute] after midnight.
String fetchTimeLabel(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

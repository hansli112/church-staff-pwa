import 'models.dart';

/// How long fetched content is shown before the fixed link takes over.
const linkContentFresh = Duration(hours: 48);

/// What the home page shows for the church link: fetched content while it
/// is fresh and from the current source, otherwise the fixed link.
({String title, String body, String url}) shownChurchLink(ChurchLink link, LinkContent? content, DateTime now) {
  final fetched = content?.fetchedAt;
  final fresh =
      link.source != null &&
      content != null &&
      content.source == link.source &&
      content.title.isNotEmpty &&
      fetched != null &&
      now.difference(fetched) < linkContentFresh;
  if (!fresh) return (title: link.title, body: link.body, url: link.url);
  return (title: content.title, body: content.body, url: content.link ?? link.url);
}

/// `HH:MM` of [minute] after midnight.
String fetchTimeLabel(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

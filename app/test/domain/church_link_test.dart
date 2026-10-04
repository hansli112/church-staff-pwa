import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/church_link.dart';
import 'package:martha/domain/models.dart';

void main() {
  const src = 'https://feed.example/today.json';
  const fixed = ChurchLink(title: '教會官網', body: '歡迎', url: 'https://grace.example', source: src);
  final now = DateTime(2026, 10, 4, 9);
  LinkContent fetched({DateTime? at, String source = src, String? link = 'https://feed.example/1004'}) => LinkContent(
    source: source,
    title: '今日經文',
    body: '耶和華是我的牧者',
    link: link,
    fetchedAt: at ?? DateTime(2026, 10, 4, 4, 30),
  );

  test('fresh content from the current source is shown', () {
    final s = shownChurchLink(fixed, fetched(), now);
    expect(s.title, '今日經文');
    expect(s.url, 'https://feed.example/1004');
  });

  test('content without a link opens the fixed link', () {
    expect(shownChurchLink(fixed, fetched(link: null), now).url, 'https://grace.example');
  });

  test('after 48 hours, or from another source, or with no source, the fixed link', () {
    expect(shownChurchLink(fixed, fetched(at: DateTime(2026, 10, 2, 8, 59)), now).title, '教會官網');
    expect(shownChurchLink(fixed, fetched(at: DateTime(2026, 10, 2, 9, 1)), now).title, '今日經文');
    expect(shownChurchLink(fixed, fetched(source: 'https://old.example'), now).title, '教會官網');
    const noSource = ChurchLink(title: '教會官網', url: 'https://grace.example');
    expect(shownChurchLink(noSource, fetched(), now).title, '教會官網');
    expect(shownChurchLink(fixed, null, now).title, '教會官網');
  });

  test('a failed fetch with no earlier content keeps the fixed link', () {
    const failed = LinkContent(source: src, error: LinkFetchError.timeout);
    expect(shownChurchLink(fixed, failed, now).title, '教會官網');
  });

  test('fetch times read as HH:MM', () {
    expect(fetchTimeLabel(270), '04:30');
    expect(fetchTimeLabel(0), '00:00');
    expect(fetchTimeLabel(23 * 60 + 45), '23:45');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/church_link.dart';
import 'package:martha/domain/models.dart';

void main() {
  const src = 'https://feed.example/today.json';
  const fixed = ChurchLink(title: '教會官網', body: '歡迎', url: 'https://grace.example', source: src);
  // 2026-10-04 09:00 in the church (UTC+8).
  final now = DateTime.utc(2026, 10, 4, 1);
  LinkContent fetched({
    DateTime? at,
    String source = src,
    String? link = 'https://feed.example/1004',
    String date = '2026-10-04',
  }) => LinkContent(
    source: source,
    date: date,
    title: '今日經文',
    body: '耶和華是我的牧者',
    link: link,
    fetchedAt: at ?? DateTime.utc(2026, 10, 3, 20, 30),
  );

  test('today’s content from the current source is shown', () {
    final s = shownChurchLink(fixed, fetched(), now)!;
    expect(s.title, '今日經文');
    expect(s.url, 'https://feed.example/1004');
  });

  test('a link with no source shows the fixed link', () {
    const noSource = ChurchLink(title: '教會官網', url: 'https://grace.example');
    expect(shownChurchLink(noSource, fetched(), now)!.title, '教會官網');
    expect(shownChurchLink(noSource, null, now)!.url, 'https://grace.example');
  });

  test('a sourced link shows nothing rather than stand in for missing content', () {
    expect(shownChurchLink(fixed, null, now), isNull);
    expect(shownChurchLink(fixed, fetched(link: null), now), isNull, reason: 'the source must give its link');
    expect(shownChurchLink(fixed, fetched(source: 'https://old.example'), now), isNull);
    expect(shownChurchLink(fixed, fetched(date: '2026-10-03'), now), isNull, reason: 'yesterday is not today');
    expect(
      shownChurchLink(fixed, fetched(at: DateTime.utc(2026, 10, 3, 15, 59)), now),
      isNull,
      reason: 'fetched before the church’s midnight',
    );
    const failed = LinkContent(source: src, error: LinkFetchError.timeout);
    expect(shownChurchLink(fixed, failed, now), isNull);
  });

  test('fetch times read as HH:MM', () {
    expect(fetchTimeLabel(270), '04:30');
    expect(fetchTimeLabel(0), '00:00');
    expect(fetchTimeLabel(23 * 60 + 45), '23:45');
  });
}

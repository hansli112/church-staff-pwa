import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/church_link.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('每日來源失敗不顯示舊內容或固定連結冒充成功', () {
    const link = ChurchLink(title: '固定連結', url: 'https://church.example.org', source: 'https://feed.example.org/today');
    final now = DateTime.utc(2026, 10, 1, 2);
    final content = LinkContent(
      source: link.source!,
      title: '先前抓到的內容',
      body: '舊內容',
      link: 'https://church.example.org/old',
      fetchedAt: now.subtract(const Duration(minutes: 1)),
      error: LinkFetchError.network,
      errorAt: now,
    );
    expect(shownChurchLink(link, content, now), isNull);
  });

  test('昨天的每日內容即使剛讀到也不能當作今天顯示', () {
    const link = ChurchLink(title: '固定連結', url: 'https://church.example.org', source: 'https://feed.example.org/today');
    final now = DateTime.utc(2026, 10, 1, 2);
    final content = LinkContent(
      source: link.source!,
      date: '2026-09-30',
      title: '昨天內容',
      body: '舊內容',
      link: 'https://church.example.org/old',
      fetchedAt: now,
    );
    expect(shownChurchLink(link, content, now), isNull);
  });

  test('手機時鐘慢幾秒，也照樣顯示今天剛抓到的內容', () {
    const link = ChurchLink(title: '固定連結', url: 'https://church.example.org', source: 'https://feed.example.org/today');
    final now = DateTime.utc(2026, 10, 1, 2);
    final content = LinkContent(
      source: link.source!,
      date: '2026-10-01',
      title: '今日經文',
      link: 'https://church.example.org/today',
      fetchedAt: now.add(const Duration(seconds: 30)),
    );
    expect(shownChurchLink(link, content, now)?.title, '今日經文');
  });
}

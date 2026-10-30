import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/domain/models.dart';

import '../support/seed.dart';

void main() {
  test(
    'admin source retry uses current source and clears stale content on failure without rewriting the link',
    () async {
      final b = seededChurch(clock: () => DateTime.utc(2026, 10, 1, 1));
      const source = 'https://example.com/today.json';
      b.linkSourceAnswers[source] = const LinkContent(source: source, title: '今天', body: '內容');
      final church = b.church('grace');
      const link = ChurchLink(title: '固定標題', body: '固定敘述', url: 'https://example.com', source: source);
      await church.churchLink.save(link);
      expect((await church.churchLink.content().first)!.date, '2026-10-01');
      b.nextLinkResult = const LinkSourceResult(error: LinkFetchError.badFormat);
      final failed = await church.churchLink.refresh();
      expect(failed.error, LinkFetchError.badFormat);
      final content = (await church.churchLink.content().first)!;
      expect(content.title, isEmpty);
      expect(content.error, LinkFetchError.badFormat);
      expect(await church.churchLink.watch().first, link);
      b.auth.signInAs('mei@example.com', uid: staffMei.uid);
      await expectLater(
        church.churchLink.refresh(),
        throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.permissionDenied)),
      );
    },
  );
}

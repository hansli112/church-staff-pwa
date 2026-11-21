import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

// Which files on a 備註 open in the browser, and which download: the same
// as storage.rules' opensSafely.
void main() {
  test('PDFs, pictures, sound, video and plain text open; the rest download', () {
    for (final type in ['application/pdf', 'image/jpeg', 'audio/mp4', 'video/quicktime', 'text/plain']) {
      expect(opensInline(type), isTrue, reason: type);
    }
    for (final type in [
      'image/svg+xml',
      'text/html',
      'application/msword',
      'application/octet-stream',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    ]) {
      expect(opensInline(type), isFalse, reason: type);
    }
  });
}

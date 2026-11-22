import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/domain/limits.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/note_draft.dart';

/// Uploads that end when the test says.
class _Notes implements RosterNoteData {
  final uploads = <Completer<NoteFile>>[];
  final progress = <void Function(double)?>[];
  final discarded = <String>[];
  RosterNote? saved;
  Object? saveFails;

  @override
  Future<NoteFile> upload(
    String rosterId, {
    required String name,
    required String type,
    required Uint8List bytes,
    void Function(double done)? onProgress,
  }) {
    progress.add(onProgress);
    return (uploads..add(Completer())).last.future;
  }

  @override
  Future<void> discard(String rosterId, NoteFile file) async => discarded.add(file.id);

  @override
  Future<void> save(String rosterId, RosterNote note) async {
    if (saveFails case final e?) throw e;
    saved = note;
  }

  @override
  Stream<Map<String, RosterNote>> watch() => const Stream.empty();
}

NoteFile _file(String id, {String name = 'a.pdf'}) =>
    NoteFile(id: id, name: name, type: 'application/pdf', size: 3, url: 'memory://$id');

final _bytes = Uint8List.fromList([1, 2, 3]);

void main() {
  test('a file shows as it goes up, then as uploaded; 完成 keeps it with the text', () async {
    final notes = _Notes();
    final draft = NoteDraft(notes, 'r', const RosterNote());
    final up = draft.upload('a.pdf', 'application/pdf', _bytes);
    expect(draft.uploading, isTrue);
    expect(draft.files.single.name, 'a.pdf');
    notes.progress.single!(0.5);
    expect(draft.progress.values.single, 0.5);

    notes.uploads.single.complete(_file('f1'));
    await up;
    expect(draft.uploading, isFalse);
    expect(draft.files, [_file('f1')]);

    await draft.save(' 帶詩歌本 ');
    expect(notes.saved!.text, '帶詩歌本');
    expect(notes.saved!.files, [_file('f1')]);
    draft.close();
    expect(notes.discarded, isEmpty, reason: 'kept');
  });

  test('closed without 完成, what went up for it goes', () async {
    final notes = _Notes();
    final draft = NoteDraft(notes, 'r', const RosterNote());
    final up = draft.upload('a.pdf', 'application/pdf', _bytes);
    notes.uploads.single.complete(_file('f1'));
    await up;
    draft.close();
    expect(notes.discarded, ['f1']);
  });

  test('one taken off, or the sheet closed, while it goes up goes once it is up', () async {
    final notes = _Notes();
    final draft = NoteDraft(notes, 'r', const RosterNote());
    final first = draft.upload('a.pdf', 'application/pdf', _bytes);
    final second = draft.upload('b.pdf', 'application/pdf', _bytes);
    draft.remove(draft.files.first);
    draft.close();
    notes.uploads[0].complete(_file('f1'));
    notes.uploads[1].complete(_file('f2', name: 'b.pdf'));
    await Future.wait([first, second]);
    expect(notes.discarded, unorderedEquals(['f1', 'f2']));
  });

  test('a file already kept and taken off stays until 完成 saves the note without it', () async {
    final notes = _Notes();
    final draft = NoteDraft(notes, 'r', RosterNote(files: [_file('old')]));
    draft.remove(_file('old'));
    expect(draft.files, isEmpty);
    expect(draft.changed(''), isTrue);
    draft.close();
    expect(notes.discarded, isEmpty);
  });

  test('one that fails to go up is taken off the list and said', () async {
    final notes = _Notes();
    final draft = NoteDraft(notes, 'r', const RosterNote());
    final up = draft.upload('a.pdf', 'application/pdf', _bytes);
    notes.uploads.single.completeError(const CloudException(CloudErrorCode.unavailable));
    await expectLater(up, throwsA(isA<CloudException>()));
    expect(draft.files, isEmpty);
    expect(draft.uploading, isFalse);
  });

  test('room for files: no more than the limit', () {
    final draft = NoteDraft(
      _Notes(),
      'r',
      RosterNote(files: [for (var i = 0; i < Limits.noteFiles - 1; i++) _file('$i')]),
    );
    expect(draft.room, 1);
  });

  test('a save that fails keeps what went up, to try again', () async {
    final notes = _Notes()..saveFails = const CloudException(CloudErrorCode.unavailable);
    final draft = NoteDraft(notes, 'r', const RosterNote());
    final up = draft.upload('a.pdf', 'application/pdf', _bytes);
    notes.uploads.single.complete(_file('f1'));
    await up;
    await expectLater(draft.save('x'), throwsA(isA<CloudException>()));
    draft.close();
    expect(notes.discarded, ['f1']);
  });
}

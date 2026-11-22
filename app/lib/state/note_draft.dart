import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/backend.dart';
import '../domain/limits.dart';
import '../domain/models.dart';

/// A day's 備註 being changed (NoteSheet): its files, each uploaded as it
/// is picked, shown as it goes up. [save] keeps them with the text; what
/// went up and is not kept goes once it is [close]d, or once it is up if it
/// was taken off or closed meanwhile.
class NoteDraft extends ChangeNotifier {
  NoteDraft(this._notes, this.rosterId, this.note) : _files = [...note.files];

  final RosterNoteData _notes;
  final String rosterId;

  /// The 備註 as it was when the sheet opened.
  final RosterNote note;

  final List<NoteFile> _files;
  final _progress = <String, double>{};
  final _previews = <String, Uint8List>{};

  /// Uploaded here and not kept yet.
  final _fresh = <NoteFile>[];
  var _picked = 0;
  var _closed = false;

  /// Its files: those uploading with a temporary ID, in [progress].
  List<NoteFile> get files => List.unmodifiable(_files);

  /// How far each file going up is, by its temporary ID.
  Map<String, double> get progress => Map.unmodifiable(_progress);

  /// A picture's bytes, shown as it goes up and after.
  Map<String, Uint8List> get previews => Map.unmodifiable(_previews);

  bool get uploading => _progress.isNotEmpty;

  /// How many more files it takes.
  int get room => Limits.noteFiles - _files.length;

  /// Whether, with [text] typed, it differs from [note].
  bool changed(String text) => text != note.text || !listEquals(_files, note.files);

  void _changed() {
    if (!_closed) notifyListeners();
  }

  void _discard(NoteFile file) => unawaited(_notes.discard(rosterId, file).catchError((_) {}));

  /// Uploads a file picked; throws, the file off the list, when it fails.
  Future<void> upload(String name, String type, Uint8List bytes) async {
    final temp = 'up${_picked++}';
    final placeholder = NoteFile(id: temp, name: name, type: type, size: bytes.length, url: '');
    _files.add(placeholder);
    _progress[temp] = 0;
    if (placeholder.isImage) _previews[temp] = bytes;
    _changed();
    final NoteFile file;
    try {
      file = await _notes.upload(
        rosterId,
        name: name,
        type: type,
        bytes: bytes,
        onProgress: (p) {
          if (_progress.containsKey(temp)) {
            _progress[temp] = p;
            _changed();
          }
        },
      );
    } on Object {
      _files.remove(placeholder);
      _progress.remove(temp);
      _previews.remove(temp);
      _changed();
      rethrow;
    }
    if (_closed || !_files.contains(placeholder)) {
      // Taken off, or the sheet closed, while it went up.
      _discard(file);
      return;
    }
    _fresh.add(file);
    _files[_files.indexOf(placeholder)] = file;
    _progress.remove(temp);
    if (_previews.remove(temp) case final bytes?) _previews[file.id] = bytes;
    _changed();
  }

  /// Takes [file] off: one uploaded here goes at once, one kept before
  /// once the note is saved without it.
  void remove(NoteFile file) {
    _files.remove(file);
    _progress.remove(file.id);
    _previews.remove(file.id);
    if (_fresh.remove(file)) _discard(file);
    _changed();
  }

  /// Keeps the note: [text] and its files.
  Future<void> save(String text) async {
    await _notes.save(rosterId, RosterNote(text: text.trim(), files: [..._files]));
    _fresh.clear();
  }

  /// The sheet closed: what went up and was not kept goes.
  void close() {
    _closed = true;
    for (final f in _fresh) {
      _discard(f);
    }
    _fresh.clear();
  }
}

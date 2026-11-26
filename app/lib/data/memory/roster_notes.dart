part of 'memory_backend.dart';

/// [RosterNoteData] of a [MemoryChurchData], refusing as saveRosterNote
/// and storage.rules do.
class _MemoryRosterNotes implements RosterNoteData {
  _MemoryRosterNotes(this._c);

  final MemoryChurchData _c;

  Map<String, RosterNote> get _notes => _c._b.rosterNotes.putIfAbsent(_c.churchId, () => {});
  Map<String, NoteFile> get _uploads => _c._b.noteUploads.putIfAbsent(_c.churchId, () => {});
  Map<String, String> get _uploaders => _c._b._noteUploaders.putIfAbsent(_c.churchId, () => {});

  static final _serviceDay = RegExp(r'^(\d{4}-\d{2}-\d{2})_(.+)$');

  /// Whoever arranges any of roster [rosterId] (Member.arranges,
  /// Member.arrangesEvent), while its last day is not gone everywhere.
  void _requireArranges(String rosterId) {
    final me = _c._b.requireMember(_c.churchId);
    final day = _serviceDay.firstMatch(rosterId);
    final Arranges arranges;
    Day? lastDay;
    if (day != null) {
      final type = day.group(2)!;
      arranges = _c._b.services[_c.churchId]!.ids.contains(type) ? me.arranges(type) : Arranges.none;
      lastDay = Day.parse(day.group(1)!);
    } else {
      final roster = _c._b.rosters[_c.churchId]![rosterId];
      arranges = roster?.forEvent == null || roster!.forEvent!.cancelled
          ? Arranges.none
          : me.arrangesEvent(roster.forEvent!.group);
      lastDay = roster?.forEvent?.lastDay;
    }
    if (!arranges.any) throw const CloudException(CloudErrorCode.permissionDenied);
    // saveRosterNote: a day before yesterday in UTC is gone.
    final yesterday = _c._b.clock().toUtc().subtract(const Duration(days: 1));
    if (lastDay != null && lastDay.isBefore(Day(yesterday.year, yesterday.month, yesterday.day))) {
      throw const CloudException(CloudErrorCode.unknown);
    }
  }

  @override
  Stream<Map<String, RosterNote>> watch() => _c._b.watch(() {
    _c._requireMember();
    return Map.of(_notes);
  }, equals: mapEquals);

  @override
  Future<NoteFile> upload(
    String rosterId, {
    required String name,
    required String type,
    required Uint8List bytes,
    void Function(double done)? onProgress,
  }) async {
    final me = _c._b.requireMember(_c.churchId);
    if (!me.isAdmin && !me.inGroup(Group.rosterEditors) && !me.leads) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    if (bytes.length > Limits.noteFileBytes || !noteFileType(type)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    late NoteFile file;
    await _c._b.write(() {
      final id = 'f${++_c._b._noteFileIds}';
      file = NoteFile(
        id: id,
        name: name,
        type: type,
        size: bytes.length,
        url: 'memory://notes/${_c.churchId}/$rosterId/$id',
      );
      _uploads['$rosterId/$id'] = file;
      _uploaders['$rosterId/$id'] = me.uid;
    });
    onProgress?.call(1);
    return file;
  }

  @override
  Future<void> discard(String rosterId, NoteFile file) async {
    final me = _c._b.requireMember(_c.churchId);
    // storage.rules: only who uploaded it takes it back.
    if (_uploaders['$rosterId/${file.id}'] != me.uid) throw const CloudException(CloudErrorCode.permissionDenied);
    await _c._b.write(() => _uploads.remove('$rosterId/${file.id}'));
  }

  @override
  Future<void> save(String rosterId, RosterNote note) async {
    _c._b.functionAccess(_c.churchId, allowed: (_) => true);
    _requireArranges(rosterId);
    final saved = _notes[rosterId]?.files ?? const <NoteFile>[];
    final ids = {for (final f in note.files) f.id};
    if (!withinTextLimit(note.text, TextLimits.rosterNote) ||
        note.files.length > Limits.noteFiles ||
        ids.length != note.files.length ||
        note.files.any((f) => f.name.trim().isEmpty || f.name.length > Limits.noteFileName)) {
      throw const CloudException(CloudErrorCode.unknown);
    }
    final files = [
      for (final f in note.files)
        if (saved.where((s) => s.id == f.id).firstOrNull case final kept?)
          kept.copyWith(name: f.name)
        else if (_uploads['$rosterId/${f.id}'] case final up?)
          up.copyWith(name: f.name)
        else
          throw const CloudException(CloudErrorCode.unknown),
    ];
    await _c._b.write(() {
      final kept = RosterNote(text: note.text, files: files);
      if (kept.isEmpty) {
        _notes.remove(rosterId);
      } else {
        _notes[rosterId] = kept;
      }
      // onRosterNoteWritten: the files taken off go.
      for (final f in saved) {
        if (!ids.contains(f.id)) _uploads.remove('$rosterId/${f.id}');
      }
    });
  }
}

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/note_draft.dart';
import '../../state/providers.dart';

/// A file picked for a 備註, before it is uploaded; no [bytes] when it is
/// over Limits.noteFileBytes, which are not read.
typedef PickedNoteFile = ({String name, String type, Uint8List? bytes});

/// Content types by extension, for files the picker gives none; any other
/// kind goes as bytes.
const _types = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'key': 'application/vnd.apple.keynote',
  'pages': 'application/vnd.apple.pages',
  'txt': 'text/plain',
};

/// Picks files for a 備註; none when cancelled. Overridden in tests.
final notePickerProvider = Provider<Future<List<PickedNoteFile>> Function()>(
  (ref) => () async {
    final picked = await FilePicker.pickFiles();
    return [
      for (final f in picked)
        (
          name: f.name,
          type: _types[f.extension?.toLowerCase()] ?? 'application/octet-stream',
          bytes: (await f.length() ?? 0) > Limits.noteFileBytes ? null : await f.readAsBytes(),
        ),
    ];
  },
);

/// Opens a note's file, out of the app.
void openNoteFile(NoteFile file) {
  if (!file.url.startsWith('http')) return;
  unawaited(launchUrl(Uri.parse(file.url), mode: LaunchMode.externalApplication));
}

/// The 備註 at the bottom of a day's roster: its text, links tappable, then
/// its pictures and files. Who arranges any of the day ([canEdit]) taps it
/// to change it, or 新增備註 when there is none; others see nothing then.
class RosterNoteSection extends ConsumerWidget {
  const RosterNoteSection({super.key, required this.rosterId, required this.canEdit});

  final String rosterId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final note = ref.watch(rosterNotesProvider.select((n) => n.value?[rosterId])) ?? const RosterNote();
    void edit() => showAppSheet<void>(
      context,
      builder: (_) => NoteSheet(rosterId: rosterId, note: note),
    );
    if (note.isEmpty) {
      if (!canEdit) return const SizedBox.shrink();
      return ListSection(
        children: [
          ListRow(title: l10n.addRosterNote, leading: const Icon(Symbols.add_rounded), onTap: edit),
        ],
      );
    }
    final c = AppColors.of(context);
    return ListSection(
      header: l10n.rosterNote,
      children: [
        InkWell(
          onTap: canEdit ? edit : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 11, Space.m, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (note.text.trim().isNotEmpty) LinkedText(note.text.trim(), style: AppText.body),
                      if (note.files.isNotEmpty) ...[
                        if (note.text.trim().isNotEmpty) const SizedBox(height: Space.s + 2),
                        NoteFiles(files: note.files),
                      ],
                    ],
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(width: Space.s),
                  Icon(Symbols.chevron_right_rounded, color: c.tertiaryLabel, size: 22),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// [text] with its web addresses tappable, opening out of the app; each
/// shown without its https://.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

final _link = RegExp(r'https?://[^\s<>"「」（）]+[^\s<>"「」（）.,;:!?。，、；：！？)\]]', caseSensitive: false);

class _LinkedTextState extends State<LinkedText> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final c = AppColors.of(context);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _link.allMatches(widget.text)) {
      if (m.start > at) spans.add(TextSpan(text: widget.text.substring(at, m.start)));
      final url = m.group(0)!;
      final tap = TapGestureRecognizer()
        ..onTap = () => unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
      _taps.add(tap);
      spans.add(
        TextSpan(
          text: url.replaceFirst(RegExp('^https?://', caseSensitive: false), ''),
          style: TextStyle(color: c.accent),
          recognizer: tap,
          semanticsLabel: url,
        ),
      );
      at = m.end;
    }
    if (at < widget.text.length) spans.add(TextSpan(text: widget.text.substring(at)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}

/// A note's files: pictures as a row of thumbnails, the rest as chips with
/// their names, each opening it. In the sheet, each has an × ([onRemove]),
/// and one still uploading a bar ([progress], by id).
class NoteFiles extends StatelessWidget {
  const NoteFiles({
    super.key,
    required this.files,
    this.onRemove,
    this.progress = const {},
    this.previews = const {},
    this.trailing,
  });

  final List<NoteFile> files;
  final ValueChanged<NoteFile>? onRemove;
  final Map<String, double> progress;

  /// Bytes of pictures just picked, by id, shown until they are uploaded.
  final Map<String, Uint8List> previews;

  /// After the chips: 加入檔案.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pictures = [
      for (final f in files)
        if (f.isImage) f,
    ];
    final others = [
      for (final f in files)
        if (!f.isImage) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pictures.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              top: onRemove == null ? 0 : 6,
              bottom: others.isEmpty && trailing == null ? 0 : 10,
            ),
            child: Wrap(
              spacing: onRemove == null ? Space.s : 12,
              runSpacing: Space.s,
              children: [
                for (final f in pictures)
                  _Thumbnail(file: f, preview: previews[f.id], progress: progress[f.id], onRemove: onRemove),
              ],
            ),
          ),
        if (others.isNotEmpty || trailing != null)
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final f in others) _Chip(file: f, progress: progress[f.id], onRemove: onRemove),
              ?trailing,
            ],
          ),
      ],
    );
  }
}

IconData _iconOf(NoteFile f) => f.isAudio
    ? Symbols.music_note_rounded
    : f.isVideo
    ? Symbols.movie_rounded
    : f.isPdf
    ? Symbols.picture_as_pdf_rounded
    : Symbols.description_rounded;

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file, this.preview, this.progress, this.onRemove});

  final NoteFile file;
  final Uint8List? preview;
  final double? progress;
  final ValueChanged<NoteFile>? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final room = ColoredBox(
      color: c.fill,
      child: Center(child: Icon(Symbols.image_rounded, color: c.tertiaryLabel)),
    );
    final bytes = preview;
    final picture = bytes != null
        ? Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, _, _) => room)
        : file.url.startsWith('http')
        ? Image.network(
            file.url,
            fit: BoxFit.cover,
            // On the web, an <img> when the bucket does not allow the page to read it.
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (_, _, _) => room,
          )
        : room;
    final remove = onRemove;
    return SizedBox.square(
      dimension: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Semantics(
              button: remove == null,
              label: file.name,
              child: Material(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.s),
                  side: BorderSide(color: c.separator, width: 0.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: remove == null ? () => openNoteFile(file) : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      picture,
                      if (progress case final p?)
                        ColoredBox(
                          color: Colors.black38,
                          child: Center(
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(value: p, strokeWidth: 3, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (remove != null)
            Positioned(
              top: -10,
              right: -10,
              child: _Remove(file: file, onRemove: remove, onPicture: true),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.file, this.progress, this.onRemove});

  final NoteFile file;
  final double? progress;
  final ValueChanged<NoteFile>? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final remove = onRemove;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        side: BorderSide(color: c.separator, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: remove == null ? () => openNoteFile(file) : null,
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34),
              child: Padding(
                padding: EdgeInsets.only(left: 10, right: remove == null ? 10 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconOf(file), size: 18, color: c.secondaryLabel),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        file.name,
                        style: AppText.subheadline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (remove != null) _Remove(file: file, onRemove: remove),
                  ],
                ),
              ),
            ),
            if (progress case final p?)
              Positioned(
                left: Space.s,
                right: Space.s,
                bottom: 3,
                child: LinearProgressIndicator(value: p, minHeight: 2, borderRadius: BorderRadius.circular(1)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The × taking a file off the note in the sheet.
class _Remove extends StatelessWidget {
  const _Remove({required this.file, required this.onRemove, this.onPicture = false});

  final NoteFile file;
  final ValueChanged<NoteFile> onRemove;
  final bool onPicture;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      label: L10n.of(context).noteRemoveFile(file.name),
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => onRemove(file),
        radius: 18,
        child: SizedBox.square(
          dimension: 32,
          child: Center(
            child: onPicture
                ? const DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: SizedBox.square(
                      dimension: 20,
                      child: Icon(Symbols.close_rounded, size: 14, color: Colors.white),
                    ),
                  )
                : Icon(Symbols.close_rounded, size: 18, color: c.tertiaryLabel),
          ),
        ),
      ),
    );
  }
}

/// Changing a day's 備註: its text, and its files, each uploaded as it is
/// picked; 完成 keeps them once they are all up.
class NoteSheet extends ConsumerStatefulWidget {
  const NoteSheet({super.key, required this.rosterId, required this.note});

  final String rosterId;
  final RosterNote note;

  @override
  ConsumerState<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<NoteSheet> {
  late final _text = TextEditingController(text: widget.note.text);

  /// Read once: an upload may end, and the sheet close, after this is gone.
  late final _draft = NoteDraft(ref.churchData.rosterNotes, widget.rosterId, widget.note)..addListener(_redraw);
  var _saving = false;

  void _redraw() => setState(() {});

  @override
  void initState() {
    super.initState();
    _draft;
  }

  @override
  void dispose() {
    // Closed without 完成: what went up for it goes.
    _draft
      ..removeListener(_redraw)
      ..close()
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final l10n = L10n.of(context);
    final picked = await ref.read(notePickerProvider)();
    if (!mounted) return;
    final room = _draft.room;
    if (picked.length > room) showToast(context, l10n.noteTooManyFiles);
    for (final f in picked.take(room)) {
      final bytes = f.bytes;
      if (bytes == null || bytes.length > Limits.noteFileBytes) {
        showToast(context, l10n.noteFileTooBig(f.name));
        continue;
      }
      unawaited(_upload(f.name, f.type, bytes));
    }
  }

  Future<void> _upload(String name, String type, Uint8List bytes) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _draft.upload(name, type, bytes);
    } on Object {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(l10n.noteFileFailed(name))));
    }
  }

  Future<void> _done() async {
    final l10n = L10n.of(context);
    setState(() => _saving = true);
    try {
      await _draft.save(_text.text);
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, l10n.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final uploading = _draft.uploading;
    return UnsavedChanges(
      changed: () => _draft.changed(_text.text),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetBar(
                title: l10n.rosterNote,
                actions: [
                  SecondaryButton(label: l10n.done, onPressed: uploading || _saving ? null : _done),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
                  children: [
                    TextField(
                      controller: _text,
                      minLines: 5,
                      maxLines: 12,
                      maxLength: TextLimits.rosterNote,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(hintText: l10n.rosterNote),
                    ),
                    const SizedBox(height: Space.s),
                    NoteFiles(
                      files: _draft.files,
                      progress: _draft.progress,
                      previews: _draft.previews,
                      onRemove: _draft.remove,
                      trailing: _draft.room <= 0
                          ? null
                          : Material(
                              color: c.accentSoft,
                              borderRadius: BorderRadius.circular(Radii.s),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: _add,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minHeight: 34),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(Space.s, 0, 12, 0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Symbols.add_rounded, size: 18, color: c.accent),
                                        const SizedBox(width: Space.xs),
                                        Text(l10n.noteAddFile, style: AppText.subheadline.copyWith(color: c.accent)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
                      child: Text(l10n.noteFilesFooter, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

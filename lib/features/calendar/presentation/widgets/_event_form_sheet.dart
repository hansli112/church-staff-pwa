import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/calendar_write_service.dart';

final _dateLabelFormat = DateFormat('yyyy/MM/dd (E)', 'zh_TW');

/// Add/edit form for a calendar event.
///
/// Submits from inside the sheet rather than handing a draft back, so the
/// spinner and any error stay next to the fields the user just filled in — a
/// SnackBar behind a modal sheet is not something people notice.
///
/// Resolves to true when the event was saved.
Future<bool> showEventFormSheet(
  BuildContext context, {
  required CalendarEventDraft initial,
  required String heading,
  required Future<void> Function(CalendarEventDraft draft) onSubmit,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // The form is taller than the default half-height sheet, and a sheet that
    // opens already scrolled looks broken.
    builder: (sheetContext) =>
        _EventFormSheet(initial: initial, heading: heading, onSubmit: onSubmit),
  );
  return saved ?? false;
}

class _EventFormSheet extends StatefulWidget {
  final CalendarEventDraft initial;
  final String heading;
  final Future<void> Function(CalendarEventDraft draft) onSubmit;

  const _EventFormSheet({
    required this.initial,
    required this.heading,
    required this.onSubmit,
  });

  @override
  State<_EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends State<_EventFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _description;

  late CalendarEventDraft _draft;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _title = TextEditingController(text: _draft.title);
    _location = TextEditingController(text: _draft.location);
    _description = TextEditingController(text: _draft.description);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  CalendarEventDraft get _current => _draft.copyWith(
    title: _title.text,
    location: _location.text,
    description: _description.text,
  );

  Future<void> _pickDate({required bool isStart}) async {
    final anchor = isStart ? _draft.startDate : _draft.endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: DateTime(anchor.year - 2),
      lastDate: DateTime(anchor.year + 3, 12, 31),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        // Moving the start past the end is almost always a person changing the
        // date of a one-day event, not asking for a negative range. Drag the
        // end along instead of making them fix a validation error.
        final shouldFollow = _draft.endDate.isBefore(picked);
        _draft = _draft.copyWith(
          startDate: picked,
          endDate: shouldFollow ? picked : _draft.endDate,
        );
      } else {
        _draft = _draft.copyWith(endDate: picked);
      }
      _error = null;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _draft.startTime : _draft.endTime,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _draft = isStart
          ? _draft.copyWith(startTime: picked)
          : _draft.copyWith(endTime: picked);
      _error = null;
    });
  }

  Future<void> _save() async {
    final draft = _current;
    final invalid = draft.validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.onSubmit(draft);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is CalendarWriteException ? error.message : '儲存失敗，請稍後再試';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.heading,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: true,
                enabled: !_submitting,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '活動名稱',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('整天'),
                value: _draft.allDay,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        _draft = _draft.copyWith(allDay: value);
                        _error = null;
                      }),
              ),
              _FieldRow(
                label: '開始',
                children: [
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.event,
                      text: _dateLabelFormat.format(_draft.startDate),
                      onPressed: _submitting
                          ? null
                          : () => _pickDate(isStart: true),
                    ),
                  ),
                  if (!_draft.allDay) ...[
                    const SizedBox(width: 8),
                    _PickerButton(
                      icon: Icons.schedule,
                      text: _draft.startTime.format(context),
                      onPressed: _submitting
                          ? null
                          : () => _pickTime(isStart: true),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              _FieldRow(
                label: '結束',
                children: [
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.event,
                      text: _dateLabelFormat.format(_draft.endDate),
                      onPressed: _submitting
                          ? null
                          : () => _pickDate(isStart: false),
                    ),
                  ),
                  if (!_draft.allDay) ...[
                    const SizedBox(width: 8),
                    _PickerButton(
                      icon: Icons.schedule,
                      text: _draft.endTime.format(context),
                      onPressed: _submitting
                          ? null
                          : () => _pickTime(isStart: false),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _location,
                enabled: !_submitting,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '地點（可不填）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                enabled: !_submitting,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '說明（可不填）',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: colorScheme.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submitting ? null : _save,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('儲存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _FieldRow({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onPressed;

  const _PickerButton({required this.icon, required this.text, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}

/// Confirms a delete. Returns true when the user chose to go ahead.
Future<bool> confirmDeleteEvent(BuildContext context, String title) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('刪除活動'),
      content: Text('確定要刪除「$title」嗎？行事曆上會直接消失。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: const Text('刪除'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

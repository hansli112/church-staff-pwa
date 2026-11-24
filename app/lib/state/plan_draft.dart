/// 安排服事's changes not saved yet (2026-11-24): while the page is open,
/// what is picked, traded and undone there stays on screen only, until
/// 完成 saves it all at once, or 放棄變更 drops it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import '../domain/roster_news.dart';

/// One day changed and not saved: as saved ([before], null for a day not
/// saved yet) and as it is now ([after], null for gone).
typedef DraftDay = ({Roster? before, Roster? after});

/// The days 安排服事 changed and has not saved, by roster ID. Held only
/// while the page is open ([hold]); every other page saves at once.
class PlanDraft extends Notifier<Map<String, DraftDay>> {
  bool _holding = false;

  /// Whether 安排服事 is open, its changes waiting here.
  bool get holding => _holding;

  @override
  Map<String, DraftDay> build() => const {};

  /// Whether [change] waits here rather than being saved: made in 安排服事
  /// while it is open.
  bool holds(RosterChange change) => _holding && change.via == RosterVia.plan;

  int _holders = 0;

  /// From now on, 安排服事's changes wait here, until [release]d by every
  /// one that held them ([release] leaves none behind).
  void hold() {
    _holders++;
    _holding = true;
  }

  /// One 安排服事 gone: once none is left, saved at once again, and
  /// whatever waited dropped.
  void release() {
    if (!ref.mounted || _holders == 0) return;
    if (--_holders > 0) return;
    _holding = false;
    state = const {};
  }

  /// [change] on top of what waits: each day keeps what is saved, takes
  /// what [change] leaves, and is no change once the two are the same.
  void add(RosterChange change) {
    final next = {...state};
    for (final MapEntry(key: id, value: after) in change.after.entries) {
      final before = next.containsKey(id) ? next[id]!.before : change.before[id];
      if (_same(before, after)) {
        next.remove(id);
      } else {
        next[id] = (before: before, after: after);
      }
    }
    state = next;
  }

  /// Everything waiting as one change to save, made in 安排服事; null
  /// with nothing. It still waits until [discard]ed, once saving shows it.
  RosterChange? get change => state.isEmpty
      ? null
      : RosterChange(
          before: {for (final MapEntry(:key, :value) in state.entries) key: value.before},
          after: {for (final MapEntry(:key, :value) in state.entries) key: value.after},
          via: RosterVia.plan,
        );

  /// Whatever waits dropped: the days as saved.
  void discard() => state = const {};

  static bool _same(Roster? a, Roster? b) => a?.copyWith(saved: true) == b?.copyWith(saved: true);
}

final planDraftProvider = NotifierProvider<PlanDraft, Map<String, DraftDay>>(PlanDraft.new);

/// [saved] with what waits in [draft] in place of the days it changed.
List<Roster> withDraft(List<Roster> saved, Map<String, DraftDay> draft) {
  if (draft.isEmpty) return saved;
  final ids = {for (final r in saved) r.id};
  final added = [
    for (final MapEntry(key: id, value: d) in draft.entries)
      if (!ids.contains(id) && d.after != null) d.after!.copyWith(saved: true),
  ];
  final out = [
    for (final r in saved)
      if (draft[r.id] case final d?) ?d.after?.copyWith(saved: true) else r,
    ...added,
  ];
  // In day order, as saved: days not saved before among them.
  if (added.isNotEmpty) out.sort((a, b) => a.day.compareTo(b.day));
  return out;
}

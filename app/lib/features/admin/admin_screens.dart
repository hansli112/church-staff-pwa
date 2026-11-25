import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/languages.dart';
import '../../data/admin_codec.dart';
import '../../data/backend.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../domain/day.dart';
import '../../state/providers.dart';
import '../../state/saved_read.dart';
import '../common/calendar_read_notice.dart';
import '../common/errors.dart';
import '../common/labels.dart';

String statusLabel(L10n l10n, ChurchStatus s) => switch (s) {
  ChurchStatus.active => l10n.statusActive,
  ChurchStatus.suspended => l10n.statusSuspended,
  ChurchStatus.deleted => l10n.statusDeleted,
};

/// The platform operator's back office: find a church, then rename it,
/// hand it to a new admin or suspend it. Every action is checked again by
/// the Cloud Function (custom claim), so this page being reachable grants
/// nothing.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

/// The newest churches, as the page opens; kept on this device, so they
/// show at once.
final _churchesProvider = AsyncNotifierProvider.autoDispose<SavedRead<ChurchPage>, Saved<ChurchPage>>(
  () => SavedRead(
    'adminChurchPage',
    read: (ref) => ref.read(backendProvider).cloud.adminChurches(),
    encode: churchPageToJson,
    decode: churchPageFromJson,
  ),
);

/// How long typing pauses before a search goes: each one reads every church.
const adminSearchPause = Duration(milliseconds: 400);

class _AdminScreenState extends ConsumerState<AdminScreen> {
  /// The churches found for [_query]; with none typed, [_churchesProvider].
  /// Null while the search for it is on its way.
  List<ChurchSummary>? _found;

  /// Why the search for [_query] failed, with nothing found to show.
  Object? _searchError;
  String _query = '';
  Timer? _typing;

  /// The churches 顯示更多 read, after the first page.
  List<ChurchSummary> _more = const [];

  /// The church to read after for 顯示更多, once it has read some; null at
  /// the last.
  String? _moreAfter;
  bool _moreRead = false;
  bool _readingMore = false;

  Future<void> _showMore(String after) async {
    if (_readingMore) return;
    setState(() => _readingMore = true);
    try {
      final page = await ref.read(backendProvider).cloud.adminChurches(after: after);
      if (!mounted) return;
      setState(() {
        _more = [..._more, ...page.churches];
        _moreAfter = page.next;
        _moreRead = true;
      });
    } catch (e) {
      if (mounted) showToast(context, errorText(L10n.of(context), e));
    } finally {
      if (mounted) setState(() => _readingMore = false);
    }
  }

  /// [id] as the backend has it now, in the churches 顯示更多 read.
  Future<void> _readAgain(String id) async {
    try {
      final found = (await ref.read(backendProvider).cloud.adminSearchChurches(id)).where((c) => c.id == id);
      if (!mounted || found.isEmpty) return;
      final now = found.first;
      setState(
        () => _more = [
          for (final c in _more)
            if (c.id != id) c else if (now.status != ChurchStatus.deleted) now,
        ],
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    _typing?.cancel();
    final query = _query;
    if (query.isEmpty) {
      setState(() => _found = null);
      // A failure shows on the list itself, with its retry.
      return _retry(ref.read(_churchesProvider.notifier));
    }
    if (_searchError != null) setState(() => _searchError = null);
    try {
      final r = await ref.read(backendProvider).cloud.adminSearchChurches(query);
      // Not one typed over since.
      if (mounted && query == _query) setState(() => _found = r);
    } catch (e) {
      if (!mounted || query != _query) return;
      // Found before (searched again on coming back): those stay.
      if (_found == null) {
        setState(() => _searchError = e);
      } else {
        showToast(context, errorText(L10n.of(context), e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final found = _found;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.operatorConsole),
        actions: [
          IconButton(
            tooltip: l10n.adminStats,
            icon: const Icon(Symbols.insights_rounded),
            onPressed: () => context.push('/admin/stats'),
          ),
          IconButton(
            tooltip: l10n.fundingCosts,
            icon: const Icon(Symbols.savings_rounded),
            onPressed: () => context.push('/admin/funding'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: SearchField(
              hint: l10n.adminSearchHint,
              onChanged: (q) {
                // Another search: not the last one's churches meanwhile.
                setState(() {
                  _query = q;
                  _found = null;
                  _searchError = null;
                });
                _typing?.cancel();
                if (q.isEmpty) {
                  _search();
                } else {
                  _typing = Timer(adminSearchPause, _search);
                }
              },
            ),
          ),
          Expanded(
            child: _query.isEmpty
                ? _SavedView(
                    value: ref.watch(_churchesProvider),
                    onRetry: () => ref.invalidate(_churchesProvider),
                    builder: (saved) {
                      final first = saved.value;
                      final shown = {for (final c in first.churches) c.id};
                      return _churches(
                        l10n,
                        [
                          ...first.churches,
                          for (final c in _more)
                            if (!shown.contains(c.id)) c,
                        ],
                        saved: saved,
                        total: first.total,
                        next: _moreRead ? _moreAfter : first.next,
                      );
                    },
                  )
                : _searchError != null
                ? ErrorRetry(message: errorText(l10n, _searchError!), onRetry: _search)
                : found == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _churches(l10n, found),
          ),
        ],
      ),
    );
  }

  /// A church opens once the list is the server's, not a kept one. The
  /// list, not a search, says how many there are ([total]) and reads more
  /// after [next].
  Widget _churches(
    L10n l10n,
    List<ChurchSummary> churches, {
    Saved<ChurchPage>? saved,
    int? total,
    String? next,
  }) {
    if (churches.isEmpty) return EmptyState(message: l10n.adminNoChurches);
    return ListView(
      children: [
        if (saved != null) _ReadNotice(saved, onRetry: () => _retry(ref.read(_churchesProvider.notifier))),
        ListSection(
          header: total == null ? null : l10n.adminChurchCount(total),
          children: [
            for (final c in churches)
              ListRow(
                title: c.name,
                subtitle: '${statusLabel(l10n, c.status)}${l10n.dotSeparator}${l10n.memberCount(c.memberCount)}',
                onTap: saved?.fresh ?? true
                    ? () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => AdminChurchScreen(summary: c)),
                        );
                        await _search();
                        if (_more.any((m) => m.id == c.id)) await _readAgain(c.id);
                      }
                    : null,
              ),
          ],
        ),
        if (next != null)
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: SecondaryButton(
              label: l10n.adminShowMore,
              busy: _readingMore,
              onPressed: () => _showMore(next),
            ),
          ),
      ],
    );
  }
}

/// Reads [read] again; a failure shows where its answer shows.
Future<void> _retry(SavedRead<Object?> read) => read.reload().then((_) {}, onError: (Object _) {});

/// Shown kept, as the server could not be read again: says so and when it
/// was read, with a retry. Nothing while the answer is the server's.
class _ReadNotice extends StatelessWidget {
  const _ReadNotice(this.saved, {required this.onRetry});

  final Saved<Object?> saved;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (saved.refreshError == null) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(child: CalendarReadNotice(status: saved.status)),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: Space.s),
          child: TextButton(onPressed: onRetry, child: Text(L10n.of(context).retry)),
        ),
      ],
    );
  }
}

/// A [SavedRead]'s page: [builder] once there is an answer to show,
/// kept or new; until then a spinner, or the error with a retry.
class _SavedView<T> extends StatelessWidget {
  const _SavedView({required this.value, required this.onRetry, required this.builder});

  final AsyncValue<Saved<T>> value;
  final VoidCallback onRetry;
  final Widget Function(Saved<T> saved) builder;

  @override
  Widget build(BuildContext context) {
    // Checked first: a refusal leaves nothing kept that may still show.
    if (value.hasError && !value.isLoading) {
      return ErrorRetry(message: errorText(L10n.of(context), value.error!), onRetry: onRetry);
    }
    final saved = value.value;
    if (value.hasError || saved == null) return const Center(child: CircularProgressIndicator.adaptive());
    return builder(saved);
  }
}

class AdminChurchScreen extends ConsumerStatefulWidget {
  const AdminChurchScreen({super.key, required this.summary});

  final ChurchSummary summary;

  @override
  ConsumerState<AdminChurchScreen> createState() => _AdminChurchScreenState();
}

/// A church's members, kept on this device per church.
final _membersProvider = AsyncNotifierProvider.autoDispose.family<SavedRead<List<Member>>, Saved<List<Member>>, String>(
  (churchId) => SavedRead(
    'adminChurchMembers/$churchId',
    read: (ref) => ref.read(backendProvider).cloud.adminChurchMembers(churchId),
    encode: churchMembersToJson,
    decode: churchMembersFromJson,
  ),
);

class _AdminChurchScreenState extends ConsumerState<AdminChurchScreen> {
  late ChurchSummary _c = widget.summary;

  /// 設為管理員 and 取消管理員 shown before the backend has them, by uid.
  final _wantAdmin = <String, bool>{};

  /// The changes, one after another: a church keeps one admin, so one
  /// member's may depend on another's, and 復原 follows what it takes back.
  Future<void> _changes = Future.value();

  /// Each member's last change: until it is read back, the row shows it.
  final _lastChange = <String, Future<void>>{};

  CloudApi get _cloud => ref.read(backendProvider).cloud;

  /// The row whose change (改名, 停用, 重新開放) is on its way: it shows a
  /// spinner, and none of them can be tapped meanwhile.
  _ChurchAction? _running;

  Future<void> _refresh() async {
    final found = await _cloud.adminSearchChurches(_c.id);
    if (found.isNotEmpty && mounted) setState(() => _c = found.first);
    try {
      await ref.read(_membersProvider(_c.id).notifier).reload();
    } catch (_) {}
  }

  Future<void> _run(_ChurchAction which, Future<void> Function() action, [String? done]) async {
    if (_running != null) return;
    final l10n = L10n.of(context);
    setState(() => _running = which);
    try {
      await action();
      if (mounted && done != null) showToast(context, done);
      // Done: the rows wait only to show what it changed.
      await _refresh().catchError((Object _) {});
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  /// [which]'s row's end: a spinner while it is on its way.
  Widget? _spinner(_ChurchAction which) => _running == which
      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
      : null;

  /// Shows [m] as admin or not at once; the backend catches up behind,
  /// and a refusal puts the row back. 復原 of 取消管理員 gives back what
  /// it took ([restore]), a whole church's 牧者 too.
  void _setAdmin(Member m, {required bool admin, Future<List<Identity>>? restore}) {
    final l10n = L10n.of(context);
    final cid = _c.id;
    setState(() => _wantAdmin[m.uid] = admin);
    Future<List<Identity>> run() async {
      if (!admin) return _cloud.adminRevokeAdmin(cid, m.uid);
      var given = const <Identity>[AdminIdentity()];
      if (restore != null) {
        try {
          given = await restore;
        } catch (_) {
          return const []; // Never taken away: nothing to give back.
        }
      }
      await _cloud.adminTransferAdmin(cid, m.uid, identities: given);
      return const [];
    }

    final change = _changes.then((_) => run());
    _changes = change.then((_) {}, onError: (Object _) {});
    _lastChange[m.uid] = change;
    showToast(
      context,
      admin ? l10n.adminMadeAdmin(m.name) : l10n.adminRevokedAdmin(m.name),
      onUndo: () {
        if (mounted) _setAdmin(m, admin: !admin, restore: admin ? null : change);
      },
    );
    void shownAsRead() {
      if (mounted && identical(_lastChange[m.uid], change)) setState(() => _wantAdmin.remove(m.uid));
    }

    change.then(
      (_) async {
        try {
          await ref.read(_membersProvider(cid).notifier).reload();
        } catch (_) {
          // Not read back: the row keeps the change, the list says it is
          // the last one read, with 重試.
          return;
        }
        shownAsRead();
      },
      onError: (Object e) {
        shownAsRead();
        if (mounted) showToast(context, errorText(l10n, e));
      },
    );
  }

  bool _isAdmin(Member m) => _wantAdmin[m.uid] ?? m.isAdmin;

  /// [m] with the button that makes them admin or not: changed only from
  /// the server's list, not a kept one.
  Widget _adminRow(L10n l10n, Member m, {required bool fresh}) => ListRow(
    title: m.name,
    subtitle: m.email,
    trailing: RowButton(
      label: _isAdmin(m) ? l10n.adminRevokeAdmin : l10n.adminMakeAdmin,
      onPressed: fresh ? () => _setAdmin(m, admin: !_isAdmin(m)) : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = _c;
    final members = ref.watch(_membersProvider(c.id));
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListRow(title: 'ID', value: c.id),
              ListRow(title: l10n.statsMembers, value: '${c.memberCount}'),
              ListRow(title: l10n.churchStatus, value: statusLabel(l10n, c.status)),
              ListRow(
                title: l10n.adminRename,
                trailing: _spinner(_ChurchAction.rename),
                onTap: _running != null
                    ? null
                    : () async {
                        final name = await promptText(
                          context,
                          title: l10n.adminRename,
                          hint: l10n.churchName,
                          initial: c.name,
                          maxLength: TextLimits.churchName,
                        );
                        if (name != null) {
                          await _run(
                            _ChurchAction.rename,
                            () => _cloud.adminRenameChurch(c.id, name),
                            l10n.saved,
                          );
                        }
                      },
              ),
            ],
          ),
          // Never read: why, with 重試.
          if (members.hasError && !members.isLoading)
            ErrorRetry(
              message: errorText(l10n, members.error!),
              onRetry: () => ref.invalidate(_membersProvider(c.id)),
            )
          // Not a spinner: the church's own rows above are already there.
          else if (members.value case final saved?) ...[
            _ReadNotice(saved, onRetry: () => _retry(ref.read(_membersProvider(c.id).notifier))),
            ListSection(
              header: l10n.members,
              children: [
                for (final m in saved.value)
                  // A church keeps one admin: theirs is not taken away here.
                  if (_isAdmin(m) && saved.value.where(_isAdmin).length == 1)
                    ListRow(title: m.name, subtitle: m.email, value: l10n.roleAdmin)
                  else
                    _adminRow(l10n, m, fresh: saved.fresh),
              ],
            ),
          ],
          if (c.status != ChurchStatus.deleted)
            ListSection(
              children: [
                if (c.status == ChurchStatus.active)
                  ListRow(
                    title: l10n.adminSuspend,
                    destructive: true,
                    trailing: _spinner(_ChurchAction.status),
                    onTap: _running != null
                        ? null
                        : () async {
                            final ok = await confirmDestructive(
                              context,
                              title: l10n.adminSuspendTitle(c.name),
                              message: l10n.adminSuspendBody,
                              action: l10n.adminSuspend,
                            );
                            if (ok) {
                              await _run(
                                _ChurchAction.status,
                                () => _cloud.adminSetStatus(
                                  c.id,
                                  ChurchStatus.suspended,
                                ),
                              );
                            }
                          },
                  )
                else
                  ListRow(
                    title: l10n.adminReopen,
                    trailing: _spinner(_ChurchAction.status),
                    onTap: _running != null
                        ? null
                        : () => _run(
                            _ChurchAction.status,
                            () => _cloud.adminSetStatus(c.id, ChurchStatus.active),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A change to the church itself, by its row on [AdminChurchScreen].
enum _ChurchAction { rename, status }

final _statsProvider = AsyncNotifierProvider.autoDispose<SavedRead<List<DailyStats>>, Saved<List<DailyStats>>>(
  () => SavedRead(
    'adminStats',
    read: (ref) => ref.read(backendProvider).cloud.adminStats(days: 30),
    encode: dailyStatsToJson,
    decode: dailyStatsFromJson,
  ),
);

/// Daily snapshots over the last 30 days: a bar a day for each metric.
/// Touching or hovering a day shows that day on every card.
class AdminStatsScreen extends ConsumerStatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  ConsumerState<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends ConsumerState<AdminStatsScreen> {
  /// The day shown, as an index into the days; null: the latest.
  int? _picked;

  /// Totals, which also show how much they changed from the day before;
  /// the rest count the 7 days to the day.
  static const _totals = {'users', 'churches_active'};

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final stats = ref.watch(_statsProvider);
    final metrics = <(String, String)>[
      ('users', l10n.statsUsers),
      ('churches_active', l10n.statsChurches),
      // Who is using it, not totals that only grow (成員 and 服事表 were).
      ('users_active_7d', l10n.statsActiveUsers),
      ('churches_editing_7d', l10n.statsChurchesEditing),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminStats)),
      body: _SavedView(
        value: stats,
        onRetry: () => ref.invalidate(_statsProvider),
        builder: (saved) {
          final days = saved.value;
          if (days.isEmpty) return EmptyState(message: l10n.statsNone);
          final ordered = [...days]..sort((a, b) => a.day.compareTo(b.day));
          final shown = (_picked ?? ordered.length - 1).clamp(0, ordered.length - 1);
          final day = ordered[shown].day;
          final thisYear = day.year == ordered.last.day.year;
          return ListView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              _ReadNotice(saved, onRetry: () => _retry(ref.read(_statsProvider.notifier))),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
                child: Text(
                  (thisYear ? DateFormat.MMMEd() : DateFormat.yMMMEd()).format(day.midnight),
                  style: AppText.title2,
                ),
              ),
              for (final (key, label) in metrics)
                if (ordered.any((d) => d.values.containsKey(key)))
                  _MetricCard(
                    label: label,
                    days: ordered,
                    metric: key,
                    shown: shown,
                    total: _totals.contains(key),
                    onPick: (i) => setState(() => _picked = i),
                  ),
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: BalancedText(
                  l10n.statsMoreInConsole,
                  textAlign: TextAlign.start,
                  style: AppText.footnote.copyWith(color: c.secondaryLabel),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One metric: its value on the day shown, and a bar for each day.
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.days,
    required this.metric,
    required this.shown,
    required this.total,
    required this.onPick,
  });

  final String label;
  final List<DailyStats> days;
  final String metric;
  final int shown;
  final bool total;

  /// A day touched or hovered; null when the pointer leaves (the latest).
  final ValueChanged<int?> onPick;

  static final _compact = NumberFormat.compact(locale: 'en');

  /// 32.5K, 729.
  String _fmt(num v) => _compact.format(v);

  /// A round number at or above [max], for the top of the bars.
  static double _ceiling(double max) {
    if (max <= 0) return 1;
    final e = math.pow(10, (math.log(max) / math.ln10).floor()).toDouble();
    for (final k in const [1, 2, 2.5, 5]) {
      if (k * e >= max) return k * e;
    }
    return 10 * e;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final values = [for (final d in days) (d.values[metric] ?? 0).toDouble()];
    final value = days[shown].values[metric];
    final change = total && shown > 0 && value != null ? value - (days[shown - 1].values[metric] ?? value) : 0;
    final top = _ceiling(values.reduce(math.max));
    final axis = AppText.caption.copyWith(color: c.secondaryLabel);
    final md = DateFormat.Md();

    int at(double x, double width) => (x / width * days.length).floor().clamp(0, days.length - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(label, style: AppText.subheadline.copyWith(color: c.secondaryLabel)),
                  ),
                  if (change != 0) ...[
                    Text(
                      change > 0 ? '+${_fmt(change)}' : '−${_fmt(-change)}',
                      style: AppText.footnote.copyWith(color: change > 0 ? c.success : c.secondaryLabel),
                    ),
                    const SizedBox(width: Space.s),
                  ],
                  Text(value == null ? '–' : _fmt(value), style: AppText.title3),
                ],
              ),
              const SizedBox(height: Space.m),
              SizedBox(
                key: Key('statsChart-$metric'),
                height: 72,
                child: LayoutBuilder(
                  builder: (context, box) => MouseRegion(
                    onHover: (e) => onPick(at(e.localPosition.dx, box.maxWidth)),
                    onExit: (_) => onPick(null),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (e) => onPick(at(e.localPosition.dx, box.maxWidth)),
                      onHorizontalDragStart: (e) => onPick(at(e.localPosition.dx, box.maxWidth)),
                      onHorizontalDragUpdate: (e) => onPick(at(e.localPosition.dx, box.maxWidth)),
                      child: Semantics(
                        label: '$label ${md.format(days.first.day.midnight)}–${md.format(days.last.day.midnight)}',
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _BarsPainter(
                            values: values,
                            top: top,
                            shown: shown,
                            bar: c.accent,
                            dim: c.accent.withValues(alpha: 0.25),
                            baseline: c.separator,
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(_fmt(top), style: axis),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  Text(md.format(days.first.day.midnight), style: axis),
                  const Spacer(),
                  Text(md.format(days.last.day.midnight), style: axis),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.top,
    required this.shown,
    required this.bar,
    required this.dim,
    required this.baseline,
  });

  final List<double> values;
  final double top;
  final int shown;
  final Color bar;
  final Color dim;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = baseline;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), line);
    // The top of the scale, dashed.
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + 3, size.width), 0.5), line);
    }
    final n = values.length;
    const gap = 3.0;
    final width = math.max(1.0, (size.width - gap * (n - 1)) / n);
    for (var i = 0; i < n; i++) {
      final h = values[i] <= 0 ? 2.0 : math.max(2.0, values[i] / top * size.height);
      final left = i * (width + gap);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - h, width, h),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        Paint()..color = i == shown ? bar : dim,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.shown != shown || old.top != top || old.bar != bar || old.dim != dim;
}

final _fundingProvider = AsyncNotifierProvider.autoDispose<SavedRead<FundingOverview>, Saved<FundingOverview>>(
  () => SavedRead(
    'adminFunding',
    read: (ref) => ref.read(backendProvider).cloud.adminFunding(),
    encode: fundingOverviewToJson,
    decode: fundingOverviewFromJson,
  ),
);

String _costValue(L10n l10n, CostItem item) {
  final amount = money(l10n, item.amount, item.currency);
  return item.per == CostPeriod.year ? l10n.costValueYear(amount) : l10n.costValueMonth(amount);
}

/// The platform's costs, which set the monthly target on the support page.
/// Only edited when a price changes; payments are counted by the backend.
class AdminFundingScreen extends ConsumerStatefulWidget {
  const AdminFundingScreen({super.key});

  @override
  ConsumerState<AdminFundingScreen> createState() => _AdminFundingScreenState();
}

class _AdminFundingScreenState extends ConsumerState<AdminFundingScreen> {
  /// The list just saved, shown until the backend has worked out its target:
  /// a save takes seconds, and the old list meanwhile looks like it failed.
  List<CostItem>? _pendingCosts;

  /// Which save [_pendingCosts] is from, so an earlier reload leaves a later
  /// save's list showing.
  int _saves = 0;

  /// Shows [items] at once and saves them; the target follows when the
  /// backend has it. Throws what the save throws, with the old list back.
  Future<void> _save(List<CostItem> items) async {
    final save = ++_saves;
    setState(() => _pendingCosts = items);
    try {
      await ref.read(backendProvider).cloud.adminSetFundingCosts(items);
    } catch (_) {
      if (mounted && save == _saves) setState(() => _pendingCosts = null);
      rethrow;
    }
    unawaited(
      ref
          .read(_fundingProvider.notifier)
          .reload()
          .then<void>(
            (_) {},
            // Saved; the list stays as it was until a reload gets through.
            onError: (Object _) {},
          )
          .whenComplete(() {
            if (mounted && save == _saves) setState(() => _pendingCosts = null);
          }),
    );
  }

  Future<void> _edit(List<CostItem> costs, int? index) async {
    final result = await showAppSheet<_CostEdit>(
      context,
      builder: (_) => _CostSheet(initial: index == null ? null : costs[index]),
    );
    if (result == null || !mounted) return;
    final next = [...costs];
    switch (result) {
      case _SaveCost(:final item) when index == null:
        next.add(item);
      case _SaveCost(:final item):
        next[index!] = item;
      case _DeleteCost():
        next.removeAt(index!);
    }
    try {
      await _save(next);
    } catch (e) {
      if (mounted) showToast(context, errorText(L10n.of(context), e));
      return;
    }
    if (result is _DeleteCost && mounted) {
      // Undo reports its own failure, so it lets the save's error through.
      final cloud = ref.read(backendProvider).cloud;
      final container = ProviderScope.containerOf(context, listen: false);
      showToast(
        context,
        L10n.of(context).deleted,
        onUndo: () async {
          if (mounted) return _save(costs);
          await cloud.adminSetFundingCosts(costs);
          container.invalidate(_fundingProvider);
        },
      );
    }
  }

  /// While a 扣回 or its 復原 is on its way: its row shows a spinner.
  bool _refunding = false;

  /// A 線上支持 payment refunded in ECPay's back office, which tells the
  /// backend nothing: taken off 雲端費用進度 by its order number.
  Future<void> _refund() async {
    final orderNo = await showAppSheet<String>(context, builder: (_) => const _RefundSheet());
    if (orderNo == null || !mounted || _refunding) return;
    final l10n = L10n.of(context);
    final cloud = ref.read(backendProvider).cloud;
    final OnlinePayment refund;
    setState(() => _refunding = true);
    try {
      refund = await cloud.adminRefundOnlineSupport(orderNo, refunded: true);
    } on CloudException catch (e) {
      final message = e.code == CloudErrorCode.notFound ? l10n.onlineRefundNotFound : errorText(l10n, e);
      if (mounted) showToast(context, message);
      return;
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
      return;
    } finally {
      if (mounted) setState(() => _refunding = false);
    }
    if (!mounted) return;
    // Taken off before: undoing this one would count a real refund again.
    if (refund.alreadyRefunded) return showToast(context, l10n.onlineRefundAlready(refund.month));
    ref.invalidate(_fundingProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    showToast(
      context,
      l10n.onlineRefunded(refund.month, money(l10n, refund.amount)),
      // A failure is said by the toast (復原失敗).
      onUndo: () async {
        if (mounted) setState(() => _refunding = true);
        try {
          await cloud.adminRefundOnlineSupport(orderNo, refunded: false);
        } finally {
          if (mounted) setState(() => _refunding = false);
        }
        container.invalidate(_fundingProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final overview = ref.watch(_fundingProvider);
    final pending = _pendingCosts;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fundingCosts)),
      body: _SavedView(
        value: overview,
        onRetry: () => ref.invalidate(_fundingProvider),
        builder: (saved) {
          final o = saved.value;
          // Costs change from the server's list only: a kept one may be out of date.
          final editable = pending == null && saved.fresh;
          return ListView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              _ReadNotice(saved, onRetry: () => _retry(ref.read(_fundingProvider.notifier))),
              ListSection(
                children: [
                  ListRow(
                    title: l10n.supportRecords,
                    value: _thisMonthCount(l10n, o.payments, ref.watch(todayProvider)),
                    onTap: () => context.push('/admin/funding/records'),
                  ),
                ],
              ),
              if (pending != null)
                ListSection(children: [ListRow(title: l10n.fundingTargetUpdating)])
              else if (o.funding case final f?)
                ListSection(
                  children: [ListRow(title: l10n.fundingTarget(money(l10n, f.target)))],
                ),
              ListSection(
                header: l10n.fundingCostsHeader,
                footer: l10n.fundingCostsFooter,
                children: [
                  for (final (i, item) in (pending ?? o.costs).indexed)
                    ListRow(
                      title: item.name,
                      value: _costValue(l10n, item),
                      onTap: editable ? () => _edit(o.costs, i) : null,
                    ),
                  ListRow(
                    title: l10n.costAdd,
                    leading: const Icon(Symbols.add_rounded),
                    onTap: editable ? () => _edit(o.costs, null) : null,
                  ),
                ],
              ),
              if (o.months.isNotEmpty)
                ListSection(
                  header: l10n.fundingMonthsHeader,
                  children: [
                    for (final m in o.months)
                      ListRow(
                        title: m.month,
                        value: l10n.fundingMonthValue(money(l10n, m.received), money(l10n, m.target)),
                      ),
                  ],
                ),
              ListSection(
                header: l10n.onlineRefundHeader,
                footer: l10n.onlineRefundFooter,
                children: [
                  ListRow(
                    title: l10n.onlineRefundAdd,
                    trailing: _refunding
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                          )
                        : null,
                    onTap: _refunding ? null : _refund,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 支持紀錄's row on 雲端費用: this month's name and how many came in.
String _thisMonthCount(L10n l10n, List<SupportPayment> payments, Day today) {
  final key = today.key.substring(0, 7);
  final count = payments.where((p) => p.month == key).length;
  return l10n.supportRecordsMonth(DateFormat.MMM().format(today.midnight), count);
}

/// The month of [key] (YYYY-MM), as a section's title: 2026年11月.
String _monthTitle(String key) {
  final [y, m] = key.split('-').map(int.parse).toList();
  return DateFormat.yMMMM().format(DateTime(y, m));
}

/// 支持紀錄: every 支持 paid, by the month it counts in (UTC+8), newest
/// first: what came in (NT\$, and as paid when another currency), 一次性
/// or 每月, through which store, when; one refunded says so, and counts
/// nothing. A month's title has what came in, its footer each way's
/// share. Who paid is not kept, so not shown; a 每月 payment may be a new
/// subscription or a renewal, which the stores do not tell apart here.
class AdminSupportRecordsScreen extends ConsumerStatefulWidget {
  const AdminSupportRecordsScreen({super.key});

  @override
  ConsumerState<AdminSupportRecordsScreen> createState() => _AdminSupportRecordsScreenState();
}

enum _SupportKind { all, once, monthly }

class _AdminSupportRecordsScreenState extends ConsumerState<AdminSupportRecordsScreen> {
  var _kind = _SupportKind.all;

  /// What was paid in another currency, by its code (HKD 40.80): its
  /// symbol may be \$ alone, as Hong Kong's is here, and the stores'
  /// reports have the code too.
  String _paid(SupportPayment p) {
    if (p.currency == 'TWD') return '';
    return NumberFormat.currency(locale: 'en', name: p.currency, symbol: '${p.currency} ').format(p.amount);
  }

  String _store(L10n l10n, PaymentStore store) => switch (store) {
    PaymentStore.apple => 'App Store',
    PaymentStore.google => 'Google Play',
    PaymentStore.ecpay => l10n.paidOnWeb,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final overview = ref.watch(_fundingProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportRecords)),
      body: _SavedView(
        value: overview,
        onRetry: () => ref.invalidate(_fundingProvider),
        builder: (saved) {
          final shown = [
            for (final p in saved.value.payments)
              if (switch (_kind) {
                _SupportKind.all => true,
                _SupportKind.once => !p.monthly,
                _SupportKind.monthly => p.monthly,
              })
                p,
          ];
          final byMonth = <String, List<SupportPayment>>{};
          for (final p in shown) {
            (byMonth[p.month] ??= []).add(p);
          }
          final time = DateFormat('M/d HH:mm');
          int sum(Iterable<SupportPayment> ps) => ps.fold(0, (n, p) => n + p.netTwd);
          return ListView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              _ReadNotice(saved, onRetry: () => _retry(ref.read(_fundingProvider.notifier))),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
                child: SegmentedButton<_SupportKind>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: _SupportKind.all, label: Text(l10n.supportKindAll)),
                    ButtonSegment(value: _SupportKind.once, label: Text(l10n.supportKindOnce)),
                    ButtonSegment(value: _SupportKind.monthly, label: Text(l10n.supportKindMonthly)),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
                ),
              ),
              if (byMonth.isEmpty) ListSection(children: [ListRow(title: l10n.supportRecordsNone)]),
              for (final MapEntry(key: month, value: payments) in byMonth.entries)
                ListSection(
                  header: '${_monthTitle(month)} · ${money(l10n, sum(payments))}',
                  footer: _kind == _SupportKind.all
                      ? l10n.supportMonthSplit(
                          money(l10n, sum(payments.where((p) => !p.monthly))),
                          money(l10n, sum(payments.where((p) => p.monthly))),
                        )
                      : null,
                  children: [
                    for (final p in payments)
                      _PaymentRow(
                        amount: money(l10n, p.amountTwd),
                        paid: _paid(p),
                        details: [
                          p.monthly ? l10n.supportKindMonthly : l10n.supportKindOnce,
                          _store(l10n, p.store),
                          if (p.refunded) time.format(p.at),
                        ].join(' · '),
                        trailing: p.refunded ? l10n.supportRefunded : time.format(p.at),
                        refunded: p.refunded,
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One row of 支持紀錄: [amount] in NT\$ and, paid in another currency,
/// [paid] beside it; [details] under it; [trailing] the time, or 已退款
/// for one [refunded], whose amount is struck through.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.amount,
    required this.paid,
    required this.details,
    required this.trailing,
    required this.refunded,
  });

  final String amount;
  final String paid;
  final String details;
  final String trailing;
  final bool refunded;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final secondary = AppText.subheadline.copyWith(color: c.secondaryLabel);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: amount,
                          style: AppText.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: refunded ? c.tertiaryLabel : c.label,
                            decoration: refunded ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (paid.isNotEmpty) TextSpan(text: '  $paid', style: secondary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(details, style: secondary),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            Text(trailing, style: secondary.copyWith(color: refunded ? c.destructive : null)),
          ],
        ),
      ),
    );
  }
}

/// Asks for the order number (特店訂單編號) of a 線上支持 payment refunded
/// in ECPay's back office; closes with it.
class _RefundSheet extends StatefulWidget {
  const _RefundSheet();

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  final _orderNo = TextEditingController();

  @override
  void dispose() {
    _orderNo.dispose();
    super.dispose();
  }

  /// What ECPay takes as MerchantTradeNo: up to 20 letters and digits.
  String? get _validOrderNo {
    final no = _orderNo.text.trim();
    return RegExp(r'^[A-Za-z0-9]{1,20}$').hasMatch(no) ? no : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return UnsavedChanges(
      changed: () => _orderNo.text.trim().isNotEmpty,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetBar(
                title: l10n.onlineRefundAdd,
                actions: [
                  SecondaryButton(
                    label: l10n.onlineRefundApply,
                    onPressed: _validOrderNo == null ? null : () => Navigator.pop(context, _validOrderNo),
                  ),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: Space.m),
                  children: [
                    TextField(
                      key: const Key('refundOrderNo'),
                      controller: _orderNo,
                      autofocus: true,
                      autocorrect: false,
                      maxLength: 20,
                      decoration: InputDecoration(labelText: l10n.onlineRefundOrderNo),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: Space.m),
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

/// What the cost sheet closed with.
sealed class _CostEdit {}

class _SaveCost extends _CostEdit {
  _SaveCost(this.item);

  final CostItem item;
}

class _DeleteCost extends _CostEdit {}

class _CostSheet extends StatefulWidget {
  const _CostSheet({this.initial});

  final CostItem? initial;

  @override
  State<_CostSheet> createState() => _CostSheetState();
}

class _CostSheetState extends State<_CostSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');

  /// Its name in the other languages, for the support pages.
  late final _names = {
    for (final l in AppLanguage.values)
      if (l != AppLanguage.zhHant) l: TextEditingController(text: widget.initial?.names[l] ?? ''),
  };
  late final _amount = TextEditingController(text: widget.initial == null ? '' : '${widget.initial!.amount}');
  late Currency _currency = widget.initial?.currency ?? Currency.twd;
  late CostPeriod _per = widget.initial?.per ?? CostPeriod.month;

  @override
  void dispose() {
    _name.dispose();
    for (final c in _names.values) {
      c.dispose();
    }
    _amount.dispose();
    super.dispose();
  }

  CostItem? get _item {
    final name = _name.text.trim();
    final amount = num.tryParse(_amount.text.trim());
    if (name.isEmpty || amount == null || amount <= 0) return null;
    return CostItem(
      name: name,
      names: {
        for (final MapEntry(key: l, value: c) in _names.entries)
          if (c.text.trim() case final n when n.isNotEmpty) l: n,
      },
      amount: amount,
      currency: _currency,
      per: _per,
    );
  }

  /// Whether any field differs from what the sheet opened with.
  bool get _changed {
    final was = widget.initial;
    return _name.text.trim() != (was?.name ?? '') ||
        _amount.text.trim() != (was == null ? '' : '${was.amount}') ||
        _currency != (was?.currency ?? Currency.twd) ||
        _per != (was?.per ?? CostPeriod.month) ||
        _names.entries.any((e) => e.value.text.trim() != (was?.names[e.key] ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return UnsavedChanges(
      changed: () => _changed,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetBar(
                title: l10n.costEdit,
                actions: [
                  SecondaryButton(
                    label: l10n.save,
                    onPressed: _item == null ? null : () => Navigator.pop<_CostEdit>(context, _SaveCost(_item!)),
                  ),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: Space.m),
                  children: [
                    TextField(
                      key: const Key('costName'),
                      controller: _name,
                      maxLength: TextLimits.costName,
                      decoration: InputDecoration(labelText: l10n.costName),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: Space.s),
                    Text(l10n.costNamesOther, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
                    for (final MapEntry(key: l, value: controller) in _names.entries)
                      TextField(
                        key: Key('costName-${l.tag}'),
                        controller: controller,
                        maxLength: TextLimits.costName,
                        decoration: InputDecoration(labelText: l.label),
                      ),
                    TextField(
                      key: const Key('costAmount'),
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: l10n.costAmount),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: Space.m),
                    SegmentedButton<Currency>(
                      showSelectedIcon: false,
                      segments: [
                        for (final c in Currency.values) ButtonSegment(value: c, label: Text(currencyLabel(l10n, c))),
                      ],
                      selected: {_currency},
                      onSelectionChanged: (v) => setState(() => _currency = v.first),
                    ),
                    const SizedBox(height: Space.s),
                    SegmentedButton<CostPeriod>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: CostPeriod.month, label: Text(l10n.costPerMonth)),
                        ButtonSegment(value: CostPeriod.year, label: Text(l10n.costPerYear)),
                      ],
                      selected: {_per},
                      onSelectionChanged: (v) => setState(() => _per = v.first),
                    ),
                    const SizedBox(height: Space.l),
                    if (widget.initial != null)
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: c.destructive),
                        onPressed: () => Navigator.pop<_CostEdit>(context, _DeleteCost()),
                        child: Text(l10n.delete),
                      ),
                    const SizedBox(height: Space.m),
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

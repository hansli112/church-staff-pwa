import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/admin_codec.dart';
import '../../data/backend.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/saved_read.dart';
import '../common/calendar_read_notice.dart';
import '../common/errors.dart';
import '../common/labels.dart';
import '../me/services_screen.dart' show promptText;

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

/// Every church, as the page opens; kept on this device, so it shows at once.
final _churchesProvider = AsyncNotifierProvider.autoDispose<SavedRead<List<ChurchSummary>>, Saved<List<ChurchSummary>>>(
  () => SavedRead(
    'adminChurches',
    read: (ref) => ref.read(backendProvider).cloud.adminSearchChurches(''),
    encode: churchSummariesToJson,
    decode: churchSummariesFromJson,
  ),
);

class _AdminScreenState extends ConsumerState<AdminScreen> {
  /// The churches found for [_query]; with none typed, [_churchesProvider].
  List<ChurchSummary>? _found;
  String _query = '';

  Future<void> _search() async {
    if (_query.isEmpty) {
      setState(() => _found = null);
      // A failure shows on the list itself, with its retry.
      return _retry(ref.read(_churchesProvider.notifier));
    }
    try {
      final r = await ref.read(backendProvider).cloud.adminSearchChurches(_query);
      if (mounted) setState(() => _found = r);
    } catch (e) {
      if (mounted) showToast(context, errorText(L10n.of(context), e));
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
                _query = q;
                _search();
              },
            ),
          ),
          Expanded(
            child: _query.isEmpty
                ? _SavedView(
                    value: ref.watch(_churchesProvider),
                    onRetry: () => ref.invalidate(_churchesProvider),
                    builder: (saved) => _churches(l10n, saved.value, saved: saved),
                  )
                : found == null
                ? const SizedBox.shrink()
                : _churches(l10n, found),
          ),
        ],
      ),
    );
  }

  /// A church opens once the list is the server's, not a kept one.
  Widget _churches(L10n l10n, List<ChurchSummary> churches, {Saved<List<ChurchSummary>>? saved}) {
    if (churches.isEmpty) return EmptyState(message: l10n.adminNoChurches);
    return ListView(
      children: [
        if (saved != null) _ReadNotice(saved, onRetry: () => _retry(ref.read(_churchesProvider.notifier))),
        ListSection(
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
                      }
                    : null,
              ),
          ],
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

  CloudApi get _cloud => ref.read(backendProvider).cloud;

  Future<void> _refresh() async {
    final found = await _cloud.adminSearchChurches(_c.id);
    if (found.isNotEmpty && mounted) setState(() => _c = found.first);
    try {
      await ref.read(_membersProvider(_c.id).notifier).reload();
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    final l10n = L10n.of(context);
    try {
      await action();
      await _refresh();
      if (mounted && done != null) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }

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
                onTap: () async {
                  final name = await promptText(
                    context,
                    title: l10n.adminRename,
                    hint: l10n.churchName,
                    initial: c.name,
                    maxLength: TextLimits.churchName,
                  );
                  if (name != null) {
                    await _run(
                      () => _cloud.adminRenameChurch(c.id, name),
                      l10n.saved,
                    );
                  }
                },
              ),
            ],
          ),
          // Not a spinner: the church's own rows above are already there.
          if (members.hasError ? null : members.value case final saved?) ...[
            _ReadNotice(saved, onRetry: () => _retry(ref.read(_membersProvider(c.id).notifier))),
            ListSection(
              header: l10n.members,
              children: [
                for (final m in saved.value)
                  ListRow(
                    title: m.name,
                    subtitle: m.email,
                    value: m.isAdmin ? l10n.roleAdmin : null,
                    // Made admin only from the server's list, not a kept one.
                    onTap: m.isAdmin || !saved.fresh
                        ? null
                        : () => _run(
                            () => _cloud.adminTransferAdmin(c.id, m.uid),
                            l10n.adminMadeAdmin(m.name),
                          ),
                  ),
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
                    onTap: () async {
                      final ok = await confirmDestructive(
                        context,
                        title: l10n.adminSuspendTitle(c.name),
                        message: l10n.adminSuspendBody,
                        action: l10n.adminSuspend,
                      );
                      if (ok) {
                        await _run(
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
                    onTap: () => _run(
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

final _statsProvider = AsyncNotifierProvider.autoDispose<SavedRead<List<DailyStats>>, Saved<List<DailyStats>>>(
  () => SavedRead(
    'adminStats',
    read: (ref) => ref.read(backendProvider).cloud.adminStats(days: 60),
    encode: dailyStatsToJson,
    decode: dailyStatsFromJson,
  ),
);

/// Daily snapshots over the last 60 days, one small trend per metric.
class AdminStatsScreen extends ConsumerWidget {
  const AdminStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final stats = ref.watch(_statsProvider);
    final metrics = <(String, String)>[
      ('users', l10n.statsUsers),
      ('churches_active', l10n.statsChurches),
      ('members', l10n.statsMembers),
      ('rosters', l10n.statsRosters),
      ('firestore_reads', l10n.statsReads),
      ('firestore_writes', l10n.statsWrites),
      ('cost_usd', l10n.statsCost),
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
          return ListView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              _ReadNotice(saved, onRetry: () => _retry(ref.read(_statsProvider.notifier))),
              for (final (key, label) in metrics)
                if (ordered.any((d) => d.values.containsKey(key)))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.m,
                      Space.s,
                      Space.m,
                      Space.s,
                    ),
                    child: Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(Radii.m),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.m),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: AppText.subheadline.copyWith(
                                      color: c.secondaryLabel,
                                    ),
                                  ),
                                ),
                                Text(
                                  _fmt(ordered.last.values[key]),
                                  style: AppText.title3,
                                ),
                              ],
                            ),
                            const SizedBox(height: Space.s),
                            SizedBox(
                              height: 64,
                              child: Semantics(
                                label: '$label ${ordered.first.day.key}–${ordered.last.day.key}',
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: _TrendPainter(
                                    [
                                      for (final d in ordered) (d.values[key] ?? 0).toDouble(),
                                    ],
                                    c.accent,
                                    c.separator,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: Space.xs),
                            Row(
                              children: [
                                Text(
                                  ordered.first.day.key,
                                  style: AppText.caption.copyWith(
                                    color: c.secondaryLabel,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  ordered.last.day.key,
                                  style: AppText.caption.copyWith(
                                    color: c.secondaryLabel,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
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

  static String _fmt(num? v) {
    if (v == null) return '–';
    if (v is double && v != v.roundToDouble()) return v.toStringAsFixed(2);
    return v.round().toString();
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color, this.baseline);

  final List<double> values;
  final Color color;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = baseline,
    );
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? size.width : size.width * i / (values.length - 1);
      final y = size.height - (values[i] - minV) / span * (size.height - 4) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.values != values || old.color != color;
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

  /// A 線上支持 payment refunded in ECPay's back office, which tells the
  /// backend nothing: taken off 雲端費用進度 by its order number.
  Future<void> _refund() async {
    final orderNo = await showAppSheet<String>(context, builder: (_) => const _RefundSheet());
    if (orderNo == null || !mounted) return;
    final l10n = L10n.of(context);
    final cloud = ref.read(backendProvider).cloud;
    final OnlinePayment refund;
    try {
      refund = await cloud.adminRefundOnlineSupport(orderNo, refunded: true);
    } on CloudException catch (e) {
      final message = e.code == CloudErrorCode.notFound ? l10n.onlineRefundNotFound : errorText(l10n, e);
      if (mounted) showToast(context, message);
      return;
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
      return;
    }
    if (!mounted) return;
    // Taken off before: undoing this one would count a real refund again.
    if (refund.alreadyRefunded) return showToast(context, l10n.onlineRefundAlready(refund.month));
    ref.invalidate(_fundingProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    showToast(
      context,
      l10n.onlineRefunded(refund.month, money(l10n, refund.amount)),
      onUndo: () async {
        await cloud.adminRefundOnlineSupport(orderNo, refunded: false);
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
                children: [ListRow(title: l10n.onlineRefundAdd, onTap: _refund)],
              ),
            ],
          );
        },
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          children: [
            Text(l10n.onlineRefundAdd, style: AppText.title3),
            const SizedBox(height: Space.m),
            TextField(
              key: const Key('refundOrderNo'),
              controller: _orderNo,
              autofocus: true,
              autocorrect: false,
              maxLength: 20,
              decoration: InputDecoration(labelText: l10n.onlineRefundOrderNo),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.l),
            PrimaryButton(
              label: l10n.onlineRefundApply,
              onPressed: _validOrderNo == null ? null : () => Navigator.pop(context, _validOrderNo),
            ),
            const SizedBox(height: Space.m),
          ],
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
  late final _amount = TextEditingController(text: widget.initial == null ? '' : '${widget.initial!.amount}');
  late Currency _currency = widget.initial?.currency ?? Currency.twd;
  late CostPeriod _per = widget.initial?.per ?? CostPeriod.month;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  CostItem? get _item {
    final name = _name.text.trim();
    final amount = num.tryParse(_amount.text.trim());
    if (name.isEmpty || amount == null || amount <= 0) return null;
    return CostItem(name: name, amount: amount, currency: _currency, per: _per);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          children: [
            Text(l10n.costEdit, style: AppText.title3),
            const SizedBox(height: Space.m),
            TextField(
              key: const Key('costName'),
              controller: _name,
              maxLength: TextLimits.costName,
              decoration: InputDecoration(labelText: l10n.costName),
              onChanged: (_) => setState(() {}),
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
            PrimaryButton(
              label: l10n.save,
              onPressed: _item == null ? null : () => Navigator.pop<_CostEdit>(context, _SaveCost(_item!)),
            ),
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
    );
  }
}

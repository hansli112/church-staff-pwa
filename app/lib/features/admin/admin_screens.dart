import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
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

class _AdminScreenState extends ConsumerState<AdminScreen> {
  List<ChurchSummary>? _results;
  String _query = '';

  Future<void> _search() async {
    try {
      final r = await ref.read(backendProvider).cloud.adminSearchChurches(_query);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) showToast(context, errorText(L10n.of(context), e));
    }
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.operatorConsole),
        actions: [
          IconButton(
            tooltip: l10n.adminStats,
            icon: const Icon(Icons.insights),
            onPressed: () => context.push('/admin/stats'),
          ),
          IconButton(
            tooltip: l10n.fundingCosts,
            icon: const Icon(Icons.savings_outlined),
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
            child: results == null
                ? const SizedBox.shrink()
                : results.isEmpty
                ? EmptyState(message: l10n.adminNoChurches)
                : ListView(
                    children: [
                      ListSection(
                        children: [
                          for (final c in results)
                            ListRow(
                              title: c.name,
                              subtitle: '${statusLabel(l10n, c.status)}・${l10n.memberCount(c.memberCount)}',
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AdminChurchScreen(summary: c),
                                  ),
                                );
                                await _search();
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminChurchScreen extends ConsumerStatefulWidget {
  const AdminChurchScreen({super.key, required this.summary});

  final ChurchSummary summary;

  @override
  ConsumerState<AdminChurchScreen> createState() => _AdminChurchScreenState();
}

class _AdminChurchScreenState extends ConsumerState<AdminChurchScreen> {
  late ChurchSummary _c = widget.summary;
  List<Member>? _members;

  CloudApi get _cloud => ref.read(backendProvider).cloud;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await _cloud.adminChurchMembers(_c.id);
      if (mounted) setState(() => _members = members);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    final found = await _cloud.adminSearchChurches(_c.id);
    if (found.isNotEmpty && mounted) setState(() => _c = found.first);
    await _load();
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
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListRow(title: 'ID', value: c.id),
              ListRow(title: l10n.statsMembers, value: '${c.memberCount}'),
              ListRow(title: l10n.role, value: statusLabel(l10n, c.status)),
              ListRow(
                title: l10n.adminRename,
                onTap: () async {
                  final name = await promptText(
                    context,
                    title: l10n.adminRename,
                    hint: l10n.churchName,
                    initial: c.name,
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
          if (_members != null)
            ListSection(
              header: l10n.members,
              children: [
                for (final m in _members!)
                  ListRow(
                    title: m.name,
                    subtitle: m.email,
                    value: roleLabel(l10n, m.role),
                    onTap: m.isAdmin
                        ? null
                        : () => _run(
                            () => _cloud.adminTransferAdmin(c.id, m.uid),
                            l10n.adminMadeAdmin(m.name),
                          ),
                  ),
              ],
            ),
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

final _statsProvider = FutureProvider.autoDispose<List<DailyStats>>(
  (ref) => ref.watch(backendProvider).cloud.adminStats(days: 60),
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
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => ErrorRetry(
          message: errorText(l10n, e),
          onRetry: () => ref.invalidate(_statsProvider),
        ),
        data: (days) {
          if (days.isEmpty) return EmptyState(message: l10n.statsNone);
          final ordered = [...days]..sort((a, b) => a.day.compareTo(b.day));
          return ListView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
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
                child: Text(
                  l10n.statsMoreInConsole,
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

final _fundingProvider = FutureProvider.autoDispose<FundingOverview>(
  (ref) => ref.watch(backendProvider).cloud.adminFunding(),
);

String _costValue(L10n l10n, CostItem item) {
  final amount = money(l10n, item.amount, item.currency);
  return item.per == CostPeriod.year ? l10n.costValueYear(amount) : l10n.costValueMonth(amount);
}

/// The platform's costs, which set the monthly target on the support page.
/// Only edited when a price changes; payments are counted by the backend.
class AdminFundingScreen extends ConsumerWidget {
  const AdminFundingScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, List<CostItem> items) async {
    try {
      await ref.read(backendProvider).cloud.adminSetFundingCosts(items);
      ref.invalidate(_fundingProvider);
    } catch (e) {
      if (context.mounted) showToast(context, errorText(L10n.of(context), e));
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, List<CostItem> costs, int? index) async {
    final result = await showAppSheet<_CostEdit>(
      context,
      builder: (_) => _CostSheet(initial: index == null ? null : costs[index]),
    );
    if (result == null || !context.mounted) return;
    final next = [...costs];
    switch (result) {
      case _SaveCost(:final item) when index == null:
        next.add(item);
      case _SaveCost(:final item):
        next[index!] = item;
      case _DeleteCost():
        next.removeAt(index!);
    }
    await _save(context, ref, next);
    if (result is _DeleteCost && context.mounted) {
      showToast(context, L10n.of(context).deleted, onUndo: () => _save(context, ref, costs));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final overview = ref.watch(_fundingProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fundingCosts)),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => ErrorRetry(
          message: errorText(l10n, e),
          onRetry: () => ref.invalidate(_fundingProvider),
        ),
        data: (o) => ListView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            if (o.funding case final f?)
              ListSection(
                children: [ListRow(title: l10n.fundingTarget(money(l10n, f.target)))],
              ),
            ListSection(
              header: l10n.fundingCostsHeader,
              footer: l10n.fundingCostsFooter,
              children: [
                for (final (i, item) in o.costs.indexed)
                  ListRow(
                    title: item.name,
                    value: _costValue(l10n, item),
                    onTap: () => _edit(context, ref, o.costs, i),
                  ),
                ListRow(
                  title: l10n.costAdd,
                  leading: const Icon(Icons.add),
                  onTap: () => _edit(context, ref, o.costs, null),
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
              maxLength: 40,
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

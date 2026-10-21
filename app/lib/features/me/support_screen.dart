import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_build.dart';
import '../../state/support.dart';
import '../common/labels.dart';
import 'me_screen.dart' show openSitePage;

final _productsProvider = FutureProvider.autoDispose<List<SupportItem>>(
  (ref) => ref.watch(supportStoreProvider).products(),
);

/// 支持馬大別忙 (iOS and Android only). Tips and two monthly plans that
/// change nothing about the app; subscribers may pick an app icon.
/// Whatever gives the same carries one name, so only the amounts show, in
/// the app's own words rather than the store's names.
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  StreamSubscription<PurchaseResult>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(supportStoreProvider).results.listen((r) {
      if (!mounted) return;
      final l10n = L10n.of(context);
      switch (r.outcome) {
        case PurchaseOutcome.thanks:
          Haptics.success();
          showToast(context, l10n.supportThanks);
        case PurchaseOutcome.pending:
          showToast(context, l10n.supportPending);
        case PurchaseOutcome.failed:
          showToast(context, l10n.supportFailed);
        case PurchaseOutcome.cancelled:
          break;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final store = ref.watch(supportStoreProvider);
    final products = ref.watch(_productsProvider);
    final supporter = ref.watch(supporterProvider);
    final plan = ref.watch(supporterPlanProvider);
    final icon = ref.watch(currentAppIconProvider).value;
    final funding = ref.watch(fundingProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.support)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BalancedText(
                  l10n.supportVerse,
                  textAlign: TextAlign.start,
                  style: AppText.body.copyWith(color: c.label, height: 1.6),
                ),
                const SizedBox(height: Space.xs),
                Text(l10n.supportVerseSource, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: Space.m),
                BalancedText(
                  l10n.supportBody,
                  textAlign: TextAlign.start,
                  style: AppText.body.copyWith(color: c.secondaryLabel),
                ),
              ],
            ),
          ),
          if (funding != null && funding.target > 0) ...[
            _FundingSection(funding),
            if (funding.costs.isNotEmpty)
              ListSection(
                header: l10n.fundingWhereItGoes,
                footer: funding.costs.any((c) => c.yearly) ? l10n.fundingYearlySplit : null,
                children: [
                  for (final cost in funding.costs) ListRow(title: cost.name, value: money(l10n, cost.perMonth)),
                ],
              ),
          ],
          products.when(
            loading: () => const SizedBox(height: 120),
            error: (_, _) => EmptyState(message: l10n.supportUnavailable),
            data: (items) {
              if (items.isEmpty) return EmptyState(message: l10n.supportComingSoon);
              final tips = items.where((i) => !i.subscription).toList();
              final monthly = items.where((i) => i.subscription).toList();
              return Column(
                children: [
                  if (tips.isNotEmpty)
                    ListSection(
                      header: l10n.supportTips,
                      children: [_Amounts(tips, label: (t) => t.price, onPick: store.buy)],
                    ),
                  // App Store 3.1.2: that it renews, how to cancel, and
                  // the terms and privacy policy, beside the subscription.
                  if (monthly.isNotEmpty)
                    ListSection(
                      header: l10n.supportMonthly,
                      footer: supporter
                          ? l10n.supportMonthlyTerms(store.name)
                          : l10n.supportMonthlyTermsAndIcons(store.name),
                      children: [
                        // The other plan switches to it.
                        _Amounts(monthly, label: (m) => l10n.supportPerMonth(m.price), paid: plan, onPick: store.buy),
                        if (plan != null)
                          ListRow(
                            title: l10n.manageSubscription,
                            onTap: () =>
                                launchUrl(store.manageSubscription(plan), mode: LaunchMode.externalApplication),
                          ),
                      ],
                    ),
                  if (monthly.isNotEmpty)
                    ListSection(
                      children: [
                        ListRow(title: l10n.termsOfService, onTap: () => openSitePage(context, ref, '/terms')),
                        ListRow(title: l10n.privacyPolicy, onTap: () => openSitePage(context, ref, '/privacy')),
                      ],
                    ),
                ],
              );
            },
          ),
          // Only what a supporter can use: a choice nobody else may make
          // is not shown to them, only named under 每月支持.
          if (supporter)
            ListSection(
              children: [
                ListRow(
                  leading: _AppIconImage(icon, size: IconTile.size),
                  title: l10n.appIcon,
                  value: appIconName(l10n, icon),
                  onTap: () => context.push('/me/support/icon'),
                ),
              ],
            ),
          // A way to support without paying.
          if (AppStore.current case final appStore? when ref.watch(storePagesPublicProvider))
            ListSection(
              children: [
                ListRow(
                  title: l10n.supportRate,
                  value: appStore.label,
                  onTap: () => launchUrl(appStore.review, mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          SecondaryButton(label: l10n.supportRestore, expand: true, onPressed: store.restore),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }
}

/// The amounts to give, side by side, one button each; stacked when large
/// text leaves them no room. [paid] (the plan paid for) is ticked and not
/// bought again.
class _Amounts extends StatelessWidget {
  const _Amounts(this.items, {required this.label, required this.onPick, this.paid});

  final List<SupportItem> items;
  final String Function(SupportItem item) label;
  final void Function(SupportItem item) onPick;
  final String? paid;

  static const _check = 18.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double widthOf(SupportItem item) {
      final text = TextPainter(
        text: TextSpan(text: label(item), style: AppText.headline),
        textScaler: scaler,
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final width = text.width;
      text.dispose();
      return width + 2 * Space.s + (item.id == paid ? _check + Space.xs : 0);
    }

    return Padding(
      padding: const EdgeInsets.all(Space.m),
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = Space.s;
          final each = (box.maxWidth - gap * (items.length - 1)) / items.length;
          final widest = items.map(widthOf).reduce(math.max);
          final width = widest <= each ? each : box.maxWidth;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  child: Semantics(
                    selected: item.id == paid,
                    child: FilledButton(
                      onPressed: item.id == paid ? null : () => onPick(item),
                      // Neutral: the accent marks only the plan paid for, a state.
                      style: FilledButton.styleFrom(
                        backgroundColor: c.fill,
                        foregroundColor: c.label,
                        disabledBackgroundColor: c.accentSoft,
                        disabledForegroundColor: c.accent,
                        minimumSize: const Size.fromHeight(50),
                        padding: const EdgeInsets.all(Space.s),
                        textStyle: AppText.headline,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.id == paid) ...[
                            const Icon(Symbols.check_rounded, size: _check),
                            const SizedBox(width: Space.xs),
                          ],
                          Flexible(child: Text(label(item), textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The home screen's rounding of an icon, as a share of its side.
const _iconRounding = 0.225;

class _AppIconImage extends StatelessWidget {
  const _AppIconImage(this.id, {required this.size});

  final String? id;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * _iconRounding),
    child: Image.asset(
      'assets/icons/${id?.toLowerCase() ?? 'app'}.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
    ),
  );
}

/// App 圖示, for supporters and the members of a church with its own icon:
/// every icon they may pick side by side, the one in use marked; tapping
/// one puts it on the home screen. Anyone with nothing to pick, or a
/// supporter whose plan lapses here, is back on [back] at once: nothing
/// shows that cannot be chosen.
class AppIconScreen extends ConsumerWidget {
  const AppIconScreen({super.key, this.back = '/me/support'});

  /// The page it opens from.
  final String back;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final choices = ref.watch(appIconChoicesProvider);
    final current = ref.watch(currentAppIconProvider).value;
    if (choices.length < 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(back);
      });
      return const Scaffold();
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appIcon)),
      body: ListView(
        children: [
          ListSection(
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.s),
                child: Wrap(
                  alignment: WrapAlignment.spaceAround,
                  runSpacing: Space.s,
                  children: [
                    for (final id in choices)
                      Semantics(
                        button: true,
                        selected: current == id,
                        label: appIconName(l10n, id),
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.m),
                          onTap: () async {
                            Haptics.selection();
                            await ref.read(currentAppIconProvider.notifier).set(id);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(Space.s),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(_size * _iconRounding + 4),
                                    border: Border.all(color: current == id ? c.accent : Colors.transparent, width: 3),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: _AppIconImage(id, size: _size),
                                  ),
                                ),
                                const SizedBox(height: Space.xs),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: _size * 1.5),
                                  child: Text(
                                    appIconName(l10n, id),
                                    textAlign: TextAlign.center,
                                    style: AppText.footnote.copyWith(color: current == id ? c.accent : c.label),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// This month's support: a bar of what is in against the target and,
/// once it is reached, how long the surplus lasts. A shortfall is not
/// spelled out: the platform operator covers it.
class _FundingSection extends StatelessWidget {
  const _FundingSection(this.funding);

  final Funding funding;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final f = funding;
    final status = f.available < f.target
        ? null
        : f.monthsLeft > 0
        ? l10n.fundingMonthsLeft(f.monthsLeft)
        : l10n.fundingEnough;
    return ListSection(
      header: l10n.fundingTitle,
      children: [
        Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.fundingProgress(money(l10n, f.available), money(l10n, f.target)), style: AppText.title3),
              const SizedBox(height: Space.s),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.s),
                child: LinearProgressIndicator(
                  value: (f.available / f.target).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: c.accent,
                  backgroundColor: c.accentSoft,
                  semanticsLabel: l10n.fundingTitle,
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: Space.s),
                BalancedText(
                  status,
                  textAlign: TextAlign.start,
                  style: AppText.subheadline.copyWith(color: c.label),
                ),
              ],
              if (f.carried > 0)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: BalancedText(
                    l10n.fundingCarried(money(l10n, f.carried)),
                    textAlign: TextAlign.start,
                    style: AppText.footnote.copyWith(color: c.secondaryLabel),
                  ),
                ),
              // Exchange Rate API's terms ask for this credit where its rates are used.
              Semantics(
                link: true,
                child: InkWell(
                  onTap: () =>
                      launchUrl(Uri.parse('https://www.exchangerate-api.com'), mode: LaunchMode.externalApplication),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: Space.minTap(Theme.of(context).platform)),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(l10n.fundingRatesBy, style: AppText.caption.copyWith(color: c.secondaryLabel)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

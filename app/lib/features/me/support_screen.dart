import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../l10n/app_localizations.dart';
import '../../state/support.dart';
import '../common/labels.dart';

final _productsProvider = FutureProvider.autoDispose<List<SupportItem>>(
  (ref) => ref.watch(supportStoreProvider).products(),
);

/// 支持馬大別忙 (iOS and Android only). Tips and a monthly subscription
/// that change nothing about the app; subscribers may pick an app icon.
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  StreamSubscription<({String productId, PurchaseOutcome outcome})>? _sub;

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

  String _iconName(L10n l10n, String? id) => switch (id) {
    'Green' => l10n.appIconGreen,
    'Purple' => l10n.appIconPurple,
    'Night' => l10n.appIconNight,
    _ => l10n.appIconDefault,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final store = ref.watch(supportStoreProvider);
    final products = ref.watch(_productsProvider);
    final supporter = ref.watch(supporterProvider);
    final icon = ref.watch(currentAppIconProvider).value;
    final funding = ref.watch(fundingProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.support)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
            child: Text(l10n.supportBody, style: AppText.body.copyWith(color: c.secondaryLabel)),
          ),
          if (funding != null && funding.target > 0) _FundingSection(funding),
          products.when(
            loading: () => const SizedBox(height: 120),
            error: (_, _) => EmptyState(message: l10n.supportUnavailable),
            data: (items) {
              if (items.isEmpty) return EmptyState(message: l10n.supportUnavailable);
              final tips = items.where((i) => !i.subscription).toList();
              final monthly = items.where((i) => i.subscription).toList();
              return Column(
                children: [
                  if (tips.isNotEmpty)
                    ListSection(
                      header: l10n.supportTips,
                      children: [
                        for (final t in tips) ListRow(title: t.title, value: t.price, onTap: () => store.buy(t)),
                      ],
                    ),
                  if (monthly.isNotEmpty)
                    ListSection(
                      header: l10n.supportMonthly,
                      children: [
                        for (final m in monthly)
                          ListRow(
                            title: m.title,
                            value: m.price,
                            trailing: supporter
                                ? Tag(label: l10n.supporterBadge, background: c.accentSoft, foreground: c.accent)
                                : null,
                            onTap: supporter ? null : () => store.buy(m),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
          ListSection(
            header: l10n.appIcon,
            footer: supporter ? null : l10n.appIconSupporterOnly,
            children: [
              for (final id in appIcons)
                ListRow(
                  title: _iconName(l10n, id),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.s),
                    child: Image.asset(
                      'assets/icons/${id?.toLowerCase() ?? 'app'}.png',
                      width: 32,
                      height: 32,
                      excludeFromSemantics: true,
                    ),
                  ),
                  selected: icon == id,
                  onTap: supporter
                      ? () async {
                          await ref.read(appIconSwitcherProvider).set(id);
                          ref.invalidate(currentAppIconProvider);
                        }
                      : null,
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

/// This month's cloud costs: a bar of what is in against the target and,
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
                Text(status, style: AppText.subheadline.copyWith(color: c.label)),
              ],
              if (f.carried > 0)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    l10n.fundingCarried(money(l10n, f.carried)),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/web_page.dart';
import '../auth/in_app_browser.dart';

/// The app is made to be used from the phone's home screen: a church URL
/// added there is an app with the church's name and icon, and an iPhone
/// gets notifications only there. So joining or starting a church on a
/// phone's browser goes through 加入主畫面 first, and the home page reminds
/// of it until dismissed.

/// How this phone adds the page to its home screen.
enum AddToHome { ios, android }

/// How [userAgent]'s phone adds the page to its home screen; null when it
/// needs not or cannot: opened from the home screen already ([standalone]),
/// a computer, a store app (no user agent), or an app's built-in browser.
AddToHome? addToHomeFor(String userAgent, {required bool standalone, required int touchPoints}) {
  if (standalone || inAppBrowser(userAgent) != null) return null;
  if (RegExp('iPhone|iPad|iPod').hasMatch(userAgent)) return AddToHome.ios;
  // An iPad asks for the desktop site, as a Mac with a touch screen.
  if (userAgent.contains('Macintosh') && touchPoints > 1) return AddToHome.ios;
  if (userAgent.contains('Android')) return AddToHome.android;
  return null;
}

final addToHomeProvider = Provider<AddToHome?>(
  (ref) => addToHomeFor(
    ref.watch(userAgentProvider),
    standalone: ref.watch(standaloneProvider),
    touchPoints: ref.watch(touchPointsProvider),
  ),
);

/// Opens 加入主畫面 for [churchId], on top of the page I am on ([push]) or
/// in its place. Only that church's own page adds it with the church's name
/// and icon, so any other page is first loaded again as that one, which
/// then comes straight here; 稍後再說 leads on to its home page.
void openAddToHome(BuildContext context, WidgetRef ref, String churchId, {bool push = true}) {
  if (ref.read(pageChurchProvider) != churchId) {
    ref.read(loadPageProvider)('/c/$churchId?to=${Uri.encodeComponent('/add-to-home')}');
  } else if (push) {
    context.push('/add-to-home');
  } else {
    context.go('/add-to-home');
  }
}

/// Where joining or starting [churchId] leads: 加入主畫面 on a phone's
/// browser, its home page anywhere else.
void goAfterJoining(BuildContext context, WidgetRef ref, String churchId) {
  if (ref.read(addToHomeProvider) == null) {
    context.go('/home');
  } else {
    openAddToHome(context, ref, churchId, push: false);
  }
}

/// The home page's reminder was dismissed on this device.
final addToHomeHiddenProvider = NotifierProvider<AddToHomeHidden, bool>(AddToHomeHidden.new);

class AddToHomeHidden extends Notifier<bool> {
  static const _key = 'add_to_home_hidden';

  @override
  bool build() => ref.watch(prefsProvider).getBool(_key) ?? false;

  void hide() {
    state = true;
    ref.read(prefsProvider).setBool(_key, true);
  }
}

/// 加入主畫面: the steps on this phone, or one tap while Chrome offers to
/// install. Right after joining it leads on to the home page; opened from
/// a page, it goes back there.
class AddToHomeScreen extends ConsumerStatefulWidget {
  const AddToHomeScreen({super.key});

  @override
  ConsumerState<AddToHomeScreen> createState() => _AddToHomeScreenState();
}

class _AddToHomeScreenState extends ConsumerState<AddToHomeScreen> {
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _install() async {
    final l10n = L10n.of(context);
    if (!await ref.read(installOfferProvider.notifier).show() || !mounted) return;
    ref.read(addToHomeHiddenProvider.notifier).hide();
    showToast(context, l10n.addToHomeDone);
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final how = ref.watch(addToHomeProvider);
    final offered = how == AddToHome.android && ref.watch(installOfferProvider);
    // Each step is what to tap, as the phone shows it, in order.
    final steps = switch (how) {
      AddToHome.ios => [
        [const _Tap(icon: Icons.more_horiz), _Tap(icon: Icons.ios_share, label: l10n.addToHomeIosShare)],
        [_Tap(icon: Icons.add_box_outlined, label: l10n.addToHome), _Tap(label: l10n.addToHomeIosAdd)],
        [_Tap(label: l10n.addToHomeIosOpen, button: false)],
        [
          _Tap(icon: Icons.person_outline, label: l10n.tabMe),
          _Tap(label: l10n.notifications),
          _Tap(label: l10n.notifEnable),
        ],
      ],
      // Nothing to add here (a computer), or Chrome does it in one tap.
      null => const <List<_Tap>>[],
      _ when offered => const <List<_Tap>>[],
      AddToHome.android => [
        [const _Tap(icon: Icons.more_vert), _Tap(icon: Icons.add_to_home_screen, label: l10n.addToHomeAndroidAdd)],
        [_Tap(label: l10n.addToHomeAndroidInstall)],
        [_Tap(label: l10n.addToHomeAndroidOpen, button: false)],
      ],
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: Space.l),
              children: [
                Icon(Icons.add_to_home_screen, size: 48, color: c.secondaryLabel),
                const SizedBox(height: Space.m),
                Text(l10n.addToHome, textAlign: TextAlign.center, style: AppText.title),
                const SizedBox(height: Space.l),
                if (steps.isNotEmpty)
                  ListSection(
                    children: [
                      for (final (i, taps) in steps.indexed) _Step(n: i + 1, taps: taps),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (offered) ...[
                        PrimaryButton(label: l10n.addToHome, onPressed: _install),
                        const SizedBox(height: Space.s),
                      ],
                      SecondaryButton(label: l10n.addToHomeLater, expand: true, onPressed: _leave),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One thing to tap in a step, drawn like the phone's own button: its
/// [icon], its [label], or both. Not a [button]: something to do instead.
class _Tap {
  const _Tap({this.icon, this.label, this.button = true});

  final IconData? icon;
  final String? label;
  final bool button;
}

/// A numbered step: its taps in order, with arrows between them. They
/// wrap onto more lines at large text sizes.
class _Step extends StatelessWidget {
  const _Step({required this.n, required this.taps});

  final int n;
  final List<_Tap> taps;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final parts = <Widget>[];
    for (final (i, tap) in taps.indexed) {
      if (i > 0) parts.add(Icon(Icons.chevron_right, size: 20, color: c.tertiaryLabel));
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tap.icon case final icon?) Icon(icon, size: 20, color: c.label),
          if (tap.icon != null && tap.label != null) const SizedBox(width: Space.xs),
          if (tap.label case final label?) Flexible(child: Text(label, style: AppText.body)),
        ],
      );
      parts.add(
        tap.button
            ? DecoratedBox(
                decoration: BoxDecoration(color: c.fill, borderRadius: BorderRadius.circular(Radii.s)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
                  child: content,
                ),
              )
            : content,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m - Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: Space.l,
            child: Text('$n', style: AppText.headline.copyWith(color: c.secondaryLabel)),
          ),
          Expanded(
            child: Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: parts,
            ),
          ),
        ],
      ),
    );
  }
}

/// The home page's 加入主畫面 row, on a phone's browser until dismissed.
class AddToHomeCard extends ConsumerWidget {
  const AddToHomeCard({super.key});

  /// Whether the home page shows it.
  static bool shown(WidgetRef ref) => ref.watch(addToHomeProvider) != null && !ref.watch(addToHomeHiddenProvider);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final churchId = ref.watch(currentChurchIdProvider);
    return ListSection(
      children: [
        ListRow(
          title: l10n.addToHome,
          subtitle: l10n.addToHomeCardBody,
          leading: const Icon(Icons.add_to_home_screen),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: l10n.addToHomeCardHide,
            onPressed: () => ref.read(addToHomeHiddenProvider.notifier).hide(),
          ),
          onTap: churchId == null ? null : () => openAddToHome(context, ref, churchId),
        ),
      ],
    );
  }
}

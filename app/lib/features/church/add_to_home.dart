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
enum AddToHome { iphone, android }

/// How [userAgent]'s phone adds the page to its home screen; null when it
/// needs not or cannot: opened from the home screen already ([standalone]),
/// a computer, a store app (no user agent), or an app's built-in browser.
AddToHome? addToHomeFor(String userAgent, {required bool standalone, required int touchPoints}) {
  if (standalone || inAppBrowser(userAgent) != null) return null;
  if (RegExp('iPhone|iPad|iPod').hasMatch(userAgent)) return AddToHome.iphone;
  // An iPad asks for the desktop site, as a Mac with a touch screen.
  if (userAgent.contains('Macintosh') && touchPoints > 1) return AddToHome.iphone;
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

/// Where joining or starting a church leads: 加入主畫面 on a phone's
/// browser, the home page anywhere else.
String afterJoining(WidgetRef ref) => ref.read(addToHomeProvider) == null ? '/home' : '/add-to-home';

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

/// 加入主畫面: why, and the steps on this phone. Chrome on Android installs
/// in one tap when it has offered to. Right after joining it leads on to
/// the home page; opened from a page, it goes back there.
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
    if (!await ref.read(installPromptProvider).show() || !mounted) return;
    showToast(context, l10n.addToHomeDone);
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final how = ref.watch(addToHomeProvider);
    final offered = how == AddToHome.android && ref.read(installPromptProvider).offered();
    final steps = switch (how) {
      AddToHome.iphone => [
        l10n.addToHomeIphoneShare,
        l10n.addToHomeIphoneAdd,
        l10n.addToHomeIphoneOpen,
        l10n.addToHomeIphoneNotif,
      ],
      // Nothing to add here (a computer), or Chrome does it in one tap.
      null => const <String>[],
      _ when offered => const <String>[],
      _ => [l10n.addToHomeAndroidMenu, l10n.addToHomeAndroidAdd, l10n.addToHomeAndroidOpen],
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Column(
                    children: [
                      Icon(Icons.add_to_home_screen, size: 48, color: c.accent),
                      const SizedBox(height: Space.m),
                      Text(l10n.addToHome, textAlign: TextAlign.center, style: AppText.title),
                      const SizedBox(height: Space.s),
                      Text(
                        l10n.addToHomeWhy,
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(color: c.secondaryLabel),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.l),
                if (steps.isNotEmpty)
                  ListSection(
                    footer: how == AddToHome.iphone ? l10n.addToHomeIphoneFooter : null,
                    children: [
                      for (final (i, step) in steps.indexed) ListRow(title: step, leading: _StepNumber(i + 1)),
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

class _StepNumber extends StatelessWidget {
  const _StepNumber(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CircleAvatar(
      radius: 12,
      backgroundColor: c.accent,
      child: Text(
        '$n',
        style: AppText.footnote.copyWith(color: c.onAccent, fontWeight: FontWeight.w600),
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
          onTap: () => context.push('/add-to-home'),
        ),
      ],
    );
  }
}

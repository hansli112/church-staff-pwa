import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/web_page.dart';
import '../auth/in_app_browser.dart';
import 'home_browser.dart';
import 'links.dart';

export 'home_browser.dart' show AddToHome, addToHomeFor;

/// Joining on a phone goes through 加入主畫面 first; the home page reminds
/// of it until dismissed. An embedded browser first needs an external one.
final addToHomeProvider = Provider<AddToHome?>(
  (ref) => addToHomeFor(
    ref.watch(userAgentProvider),
    standalone: ref.watch(standaloneProvider),
    touchPoints: ref.watch(touchPointsProvider),
  ),
);

/// Only a church's own page installs with its name and icon. Load it first
/// when needed; 稍後再說 leads on to its home page.
void openAddToHome(BuildContext context, WidgetRef ref, String churchId, {bool push = true}) {
  if (ref.read(pageChurchProvider) != churchId) {
    ref.read(loadPageProvider)('/c/$churchId?to=${Uri.encodeComponent('/add-to-home')}');
  } else if (push) {
    context.push('/add-to-home');
  } else {
    context.go('/add-to-home');
  }
}

/// Where joining or starting [churchId] leads: the guide on a phone's
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

class AddToHomeScreen extends ConsumerStatefulWidget {
  const AddToHomeScreen({super.key});

  @override
  ConsumerState<AddToHomeScreen> createState() => _AddToHomeScreenState();
}

class _AddToHomeScreenState extends ConsumerState<AddToHomeScreen> {
  HomeBrowser? _chosenBrowser;
  bool _trouble = false;

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
    final church = ref.read(churchProvider).value;
    showToast(context, l10n.addToHomeDone(church?.homeName ?? church?.name ?? l10n.appName));
    _leave();
  }

  Future<void> _chooseBrowser(AddToHome platform, HomeBrowser current) async {
    final l10n = L10n.of(context);
    final choice = await showAppSheet<HomeBrowser>(
      context,
      builder: (context) => SingleChildScrollView(
        child: ListSection(
          header: l10n.addToHomeChooseGuide,
          footer: l10n.addToHomeChooseGuideNote,
          children: [
            for (final browser in homeBrowsersFor(platform))
              ListRow(
                title: _browserName(l10n, browser),
                selected: browser == current,
                onTap: () => Navigator.pop(context, browser),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() {
      _chosenBrowser = choice;
      _trouble = false;
    });
  }

  Future<void> _copyLink(String browser) async {
    final churchId = ref.read(currentChurchIdProvider);
    if (churchId == null) return;
    // Resume this guide after opening the same church in another browser.
    await copyText(
      context,
      '${churchUrl(churchId)}?to=${Uri.encodeComponent('/add-to-home')}',
      copied: L10n.of(context).addToHomeCopiedForBrowser(browser),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final platform = ref.watch(addToHomeProvider);
    final ua = ref.watch(userAgentProvider);
    final ipad = isHomeIpad(ua, touchPoints: ref.watch(touchPointsProvider));
    final device = platform == AddToHome.ios ? (ipad ? 'iPad' : 'iPhone') : 'Android';
    final detected = platform == null ? HomeBrowser.other : homeBrowserFor(ua, platform);
    final browser = _chosenBrowser ?? detected;
    final offered =
        platform == AddToHome.android &&
        detected != HomeBrowser.inApp &&
        browser == detected &&
        ref.watch(installOfferProvider);
    final church = ref.watch(churchProvider).value;
    final iconName = church?.homeName ?? church?.name ?? l10n.appName;
    final guide = homeGuideFor(platform, browser, ipad: ipad);
    final instructions = guide == null ? null : _instructionsFor(l10n, guide, iconName);
    final external = instructions == null;
    final fallback = platform == AddToHome.ios ? 'Safari' : 'Chrome';
    final browserName = browser == HomeBrowser.inApp
        ? inAppBrowser(ua) ?? l10n.addToHomeInApp
        : _browserName(l10n, browser);

    return Scaffold(
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
          child: SecondaryButton(label: l10n.addToHomeLater, expand: true, onPressed: _leave),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: Space.l),
              children: [
                Icon(Icons.add_to_home_screen, size: 40, color: c.secondaryLabel),
                const SizedBox(height: Space.s),
                BalancedText(l10n.addToHome, style: AppText.title),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                  child: BalancedText(
                    platform == null ? l10n.addToHomePhoneOnly : l10n.addToHomeIntro,
                    style: AppText.subheadline.copyWith(color: c.secondaryLabel),
                  ),
                ),
                if (platform != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                    child: BalancedText(
                      l10n.addToHomeBrowserGuide(device, browserName),
                      style: AppText.headline,
                    ),
                  ),
                  SecondaryButton(
                    label: l10n.addToHomeChooseBrowser,
                    onPressed: () => _chooseBrowser(platform, browser),
                  ),
                  if (!offered && instructions != null)
                    ListSection(
                      footer: instructions.footer,
                      children: instructions.steps,
                    ),
                  if (!offered && external)
                    ListSection(
                      header: browser == HomeBrowser.inApp ? l10n.addToHomeEmbeddedHint : l10n.addToHomeUnknownHint,
                      children: [
                        _GuideStep(n: 1, title: l10n.churchUrlCopy, icon: Icons.copy),
                        _GuideStep(
                          n: 2,
                          title: l10n.addToHomeExternalTitle(fallback),
                          detail: l10n.addToHomeExternalHint(fallback),
                          icon: Icons.open_in_browser,
                        ),
                      ],
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (offered) ...[
                        PrimaryButton(label: l10n.addToHome, onPressed: _install),
                        const SizedBox(height: Space.s),
                      ] else if (platform != null && external)
                        PrimaryButton(
                          label: l10n.churchUrlCopy,
                          onPressed: church == null ? null : () => _copyLink(fallback),
                          icon: const Icon(Icons.copy),
                        )
                      else if (platform != null) ...[
                        SecondaryButton(
                          label: l10n.addToHomeTrouble,
                          onPressed: () => setState(() => _trouble = !_trouble),
                        ),
                        if (_trouble) ...[
                          if (platform == AddToHome.ios && browser == HomeBrowser.safari)
                            Text(l10n.addToHomeSafariTrouble, style: AppText.body),
                          Text(l10n.addToHomeExternalHint(fallback), style: AppText.body),
                          SecondaryButton(
                            label: l10n.churchUrlCopy,
                            onPressed: church == null ? null : () => _copyLink(fallback),
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ],
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

String _browserName(L10n l10n, HomeBrowser browser) => switch (browser) {
  HomeBrowser.safari => 'Safari',
  HomeBrowser.chrome => 'Chrome',
  HomeBrowser.edge => 'Edge',
  HomeBrowser.firefox => 'Firefox',
  HomeBrowser.samsung => 'Samsung Internet',
  HomeBrowser.inApp => l10n.addToHomeInApp,
  HomeBrowser.other => l10n.addToHomeOtherBrowser,
};

// Mobile instructions checked against Apple iphea86e5236 / ipad8f1f7a29,
// Google Chrome help 9658361, and Mozilla's add-website-shortcut-your-home-screen-ios
// and use-web-apps-firefox-android (2026-10-09).
({List<Widget> steps, String? footer}) _instructionsFor(L10n l10n, HomeGuide guide, String iconName) {
  final iosConfirmStep = _GuideStep(
    n: 2,
    title: l10n.addToHomeSelectAdd,
    detail: l10n.addToHomeIosConfirm,
    icon: Icons.add_box_outlined,
  );
  final (first, second, ios) = switch (guide) {
    HomeGuide.safariIphone => (
      _GuideStep(
        n: 1,
        title: l10n.addToHomeSafariShare,
        detail: l10n.addToHomeSafariShareHint,
        illustration: _GuideScreenshots(
          images: const [
            (path: 'assets/add_to_home/safari_more.png', aspectRatio: 900 / 142),
            (path: 'assets/add_to_home/safari_share.png', aspectRatio: 790 / 280),
          ],
          caption: l10n.addToHomeSafariScreenshot,
        ),
      ),
      _GuideStep(
        n: 2,
        title: l10n.addToHomeSelectAdd,
        detail: '${l10n.addToHomeShareMore}\n${l10n.addToHomeIosConfirm}',
        illustration: _GuideScreenshots(
          images: const [
            (path: 'assets/add_to_home/safari_share_more.png', aspectRatio: 900 / 385),
            (path: 'assets/add_to_home/safari_add.png', aspectRatio: 900 / 413),
          ],
          caption: l10n.addToHomeSafariScreenshot,
        ),
      ),
      true,
    ),
    HomeGuide.safariIpad => (
      _GuideStep(n: 1, title: l10n.addToHomeSafariShare, icon: Icons.ios_share),
      _GuideStep(
        n: 2,
        title: l10n.addToHomeSelectAdd,
        detail: '${l10n.addToHomeIpadMore}\n${l10n.addToHomeIosConfirm}',
        icon: Icons.add_box_outlined,
      ),
      true,
    ),
    HomeGuide.chromeIos => (
      _GuideStep(
        n: 1,
        title: l10n.addToHomeChromeShare,
        detail: l10n.addToHomeChromeShareHint,
        illustration: _GuideScreenshots(
          images: const [(path: 'assets/add_to_home/chrome_ios_share.png', aspectRatio: 900 / 115)],
          caption: l10n.addToHomeChromeIosScreenshot,
        ),
      ),
      _GuideStep(
        n: 2,
        title: l10n.addToHomeSelectAdd,
        detail: '${l10n.addToHomeChromeScroll}\n${l10n.addToHomeIosConfirm}',
        illustration: _GuideScreenshots(
          images: const [(path: 'assets/add_to_home/chrome_ios_add.png', aspectRatio: 900 / 263)],
          caption: l10n.addToHomeChromeIosScreenshot,
        ),
      ),
      true,
    ),
    HomeGuide.firefoxIos => (
      _GuideStep(n: 1, title: l10n.addToHomeFirefoxShare, icon: Icons.ios_share),
      iosConfirmStep,
      true,
    ),
    HomeGuide.chromeAndroid => (
      _GuideStep(
        n: 1,
        title: l10n.addToHomeMenu('Chrome'),
        illustration: _GuideScreenshots(
          images: const [(path: 'assets/add_to_home/chrome_android_more.png', aspectRatio: 900 / 133)],
          caption: l10n.addToHomeChromeAndroidScreenshot,
        ),
      ),
      _GuideStep(
        n: 2,
        title: l10n.addToHomeChromeInstall,
        detail: l10n.addToHomeChromeInstallHint,
        illustration: _GuideScreenshots(
          images: const [(path: 'assets/add_to_home/chrome_android_add.png', aspectRatio: 700 / 400)],
          caption: l10n.addToHomeChromeAndroidScreenshot,
        ),
      ),
      false,
    ),
    HomeGuide.firefoxAndroid => (
      _GuideStep(n: 1, title: l10n.addToHomeMenu('Firefox'), icon: Icons.more_vert),
      _GuideStep(
        n: 2,
        title: l10n.addToHomeAndroidInstall,
        detail: l10n.addToHomeFirefoxInstallHint,
        icon: Icons.add_to_home_screen,
      ),
      false,
    ),
  };
  return (
    steps: [
      first,
      second,
      _GuideStep(
        n: 3,
        title: l10n.addToHomeOpenTitle,
        detail: ios ? l10n.addToHomeIosOpen(iconName) : l10n.addToHomeAndroidOpen(iconName),
        icon: Icons.touch_app_outlined,
      ),
    ],
    footer: ios ? l10n.addToHomeNotificationsAfter : null,
  );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.n, required this.title, this.detail, this.icon, this.illustration});

  final int n;
  final String title;
  final String? detail;
  final IconData? icon;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: Space.l,
            child: Text('$n', style: AppText.headline.copyWith(color: c.secondaryLabel)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 22, color: c.secondaryLabel),
                      const SizedBox(width: Space.s),
                    ],
                    Expanded(child: Text(title, style: AppText.headline)),
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(detail!, style: AppText.subheadline.copyWith(color: c.secondaryLabel)),
                ],
                if (illustration != null) ...[const SizedBox(height: Space.s), illustration!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cropped browser captures, with only the target annotation added. Each
/// caption names the browser and version so other layouts are not implied.
class _GuideScreenshots extends StatelessWidget {
  const _GuideScreenshots({required this.images, required this.caption});

  final List<({String path, double aspectRatio})> images;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final image in images) ...[
          AspectRatio(
            aspectRatio: image.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.s),
              child: Image.asset(image.path, width: double.infinity, excludeFromSemantics: true),
            ),
          ),
          const SizedBox(height: Space.s),
        ],
        Text(L10n.of(context).addToHomeScreenshotNote, style: AppText.caption.copyWith(color: c.secondaryLabel)),
        const SizedBox(height: Space.xs),
        Text(caption, style: AppText.caption.copyWith(color: c.secondaryLabel)),
      ],
    );
  }
}

/// The home page's 加入主畫面 row, on a phone's browser until dismissed.
class AddToHomeCard extends ConsumerWidget {
  const AddToHomeCard({super.key});

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

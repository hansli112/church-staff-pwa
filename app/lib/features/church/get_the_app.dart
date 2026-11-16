import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../deep_link.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_build.dart';
import '../../state/device_flag.dart';
import '../../state/providers.dart';
import 'add_to_home.dart';
import 'church_logo.dart';
import 'links.dart';

/// 用網頁版 was chosen in this browser: its links go on here from now on.
final webChosenProvider = NotifierProvider<DeviceFlag, bool>(() => DeviceFlag('web_chosen'));

/// The store to offer the app from: on a phone's browser that has not
/// chosen the web version. Null in the app itself, on a computer, and on the
/// page added to the home screen.
final storeToOfferProvider = Provider<AppStore?>((ref) {
  if (ref.watch(webChosenProvider)) return null;
  return switch (ref.watch(addToHomeProvider)) {
    AddToHome.ios => AppStore.appStore,
    AddToHome.android => AppStore.googlePlay,
    null => null,
  };
});

/// A church's link opened in a phone's browser (an invite link, a church
/// URL) offers the app first: the web version is hard to use on a phone.
/// The link opens the app once it is installed. [link] is the page opened,
/// a path; any other page goes straight to [child].
class GetTheAppFirst extends ConsumerWidget {
  const GetTheAppFirst({super.key, required this.link, required this.child});

  final String? link;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeToOfferProvider);
    final location = appLocation(link);
    if (store == null || location == null) return child;
    final code = inviteCodeIn(location);
    final churchId = churchUrlId(Uri.parse(location));
    final String? name;
    if (code != null) {
      final invited = ref.watch(invitedChurchProvider(code));
      // An invite that does not work says so where it is opened.
      if (invited.hasError) return child;
      name = invited.value;
    } else if (churchId != null) {
      final preview = ref.watch(churchPreviewProvider(churchId));
      if (preview.hasError) return child;
      name = preview.value?.name;
    } else {
      return child;
    }
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Space.l),
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset('assets/icons/app.png', width: 88, height: 88, excludeFromSemantics: true),
                  ),
                ),
                const SizedBox(height: Space.l),
                // Room for the name while it loads, so the buttons stay put.
                Opacity(
                  opacity: name == null ? 0 : 1,
                  child: BalancedText(
                    name == null ? ' ' : (code != null ? l10n.getAppInvited(name) : name),
                    style: AppText.title2,
                  ),
                ),
                const SizedBox(height: Space.xl),
                PrimaryButton(
                  label: l10n.getAppFrom(store.label),
                  onPressed: () => launchUrl(store.page, mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: Space.s),
                BalancedText(
                  code != null ? l10n.getAppThenInvite : l10n.getAppThenChurch,
                  style: AppText.footnote.copyWith(color: c.secondaryLabel),
                ),
                const SizedBox(height: Space.xl),
                Center(
                  child: TextButton(
                    onPressed: () => ref.read(webChosenProvider.notifier).mark(),
                    child: Text(l10n.useWebVersion),
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

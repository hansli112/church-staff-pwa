import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/device_flag.dart';
import '../../state/push.dart';
import '../../state/session.dart';
import '../church/add_to_home.dart';

/// The page after joining was shown on this device: it comes once.
final notificationsAskedProvider = NotifierProvider<DeviceFlag, bool>(() => DeviceFlag('notifications_asked'));

/// The home page's 開啟通知 was dismissed on this device.
final notificationsCardHiddenProvider = NotifierProvider<DeviceFlag, bool>(
  () => DeviceFlag('notifications_card_hidden'),
);

/// Whether joining or starting a church goes through
/// [TurnOnNotificationsScreen] first. The permission is the one the session
/// loaded at sign-in; not loaded yet, the home page's card asks instead.
bool notificationsAskDue(WidgetRef ref) =>
    !ref.read(notificationsAskedProvider) && ref.read(pushPermissionProvider).value == PushPermission.notAsked;

/// Asks the phone for permission and registers this device. Registering can
/// fail even when allowed (no APNs token yet); the next launch tries again,
/// so says so instead of looking stuck. With [nudge], a dismissed prompt
/// says to tap 允許.
Future<PushPermission?> enableNotifications(BuildContext context, {bool nudge = false}) async {
  final l10n = L10n.of(context);
  // The phone's prompt sends the app to the background and back, which
  // sees notifications on and takes the home page's card away before this
  // returns, and its ref with it.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final result = await container.read(pushServiceProvider).enable();
    // Dismissed, or tucked into the address bar by the browser.
    if (nudge && result == PushPermission.notAsked && context.mounted) showToast(context, l10n.notifNotAllowed);
    return result;
  } catch (e, stack) {
    container.read(telemetryProvider).recordError(e, stack);
    if (context.mounted) showToast(context, l10n.notifRegisterFailed);
    return null;
  } finally {
    container.invalidate(pushPermissionProvider);
  }
}

/// Opens this app's notification settings on the phone. Should the phone
/// have no such page, says where to look instead.
Future<void> openNotificationSettings(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(pushServiceProvider).openSettings();
  } catch (e, stack) {
    ref.read(telemetryProvider).recordError(e, stack);
    if (context.mounted) showToast(context, L10n.of(context).notifPermissionOff);
  }
}

/// Right after joining or starting a church: what notifications bring, and
/// the phone's own prompt only once 開啟通知 is tapped. Shown once per
/// device, never on a phone's browser, where 加入主畫面 comes first.
class TurnOnNotificationsScreen extends ConsumerStatefulWidget {
  const TurnOnNotificationsScreen({super.key});

  @override
  ConsumerState<TurnOnNotificationsScreen> createState() => _TurnOnNotificationsScreenState();
}

class _TurnOnNotificationsScreenState extends ConsumerState<TurnOnNotificationsScreen> {
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    await enableNotifications(context);
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
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
                Icon(Icons.notifications_active_outlined, size: 40, color: c.secondaryLabel),
                const SizedBox(height: Space.s),
                BalancedText(l10n.notifAskTitle, style: AppText.title),
                const SizedBox(height: Space.s),
                BalancedText(l10n.notifAskBody, style: AppText.body.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: Space.xl),
                PrimaryButton(label: l10n.notifEnable, busy: _busy, onPressed: _enable),
                const SizedBox(height: Space.s),
                SecondaryButton(label: l10n.notifAskLater, expand: true, onPressed: () => context.go('/home')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The home page's 開啟通知, until it is on or dismissed. Turned off on the
/// phone, it opens the phone's settings, since the phone will not ask
/// again; a browser has no such page, so there it is not shown.
class TurnOnNotificationsCard extends ConsumerWidget {
  const TurnOnNotificationsCard({super.key});

  static bool shown(WidgetRef ref) {
    if (ref.watch(notificationsCardHiddenProvider) || ref.watch(addToHomeProvider) != null) return false;
    return switch (ref.watch(pushPermissionProvider).value) {
      PushPermission.notAsked => true,
      PushPermission.denied => ref.watch(pushServiceProvider).canOpenSettings,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final off = ref.watch(pushPermissionProvider).value == PushPermission.denied;
    return ListSection(
      children: [
        ListRow(
          title: off ? l10n.notifOpenSettings : l10n.notifEnable,
          subtitle: l10n.notifAskTitle,
          leading: const Icon(Icons.notifications_active_outlined),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: l10n.notifCardHide,
            onPressed: () => ref.read(notificationsCardHiddenProvider.notifier).mark(),
          ),
          onTap: off ? () => openNotificationSettings(context, ref) : () => enableNotifications(context, nudge: true),
        ),
      ],
    );
  }
}

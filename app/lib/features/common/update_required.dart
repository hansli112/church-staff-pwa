import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_build.dart';

/// Over the whole app while this store app is older than the backend
/// allows ([updateRequiredProvider]). The app stays underneath, hidden, so
/// sign-in, the page and whatever was typed are all there if it is lifted;
/// meanwhile nothing reaches it: not the keyboard, the back button or a toast.
///
/// It sits above the router, so its back-button observer is asked first.
class UpdateRequiredGate extends ConsumerStatefulWidget {
  const UpdateRequiredGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateRequiredGate> createState() => _UpdateRequiredGateState();
}

class _UpdateRequiredGateState extends ConsumerState<UpdateRequiredGate> with WidgetsBindingObserver {
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async => _blocked;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => _blocked;

  @override
  Widget build(BuildContext context) {
    _blocked = ref.watch(updateRequiredProvider);
    final store = ref.watch(appBuildProvider)?.store;
    return Stack(
      children: [
        Offstage(
          offstage: _blocked,
          child: TickerMode(
            enabled: !_blocked,
            child: ExcludeFocus(excluding: _blocked, child: widget.child),
          ),
        ),
        // Its own messenger: the app's toasts stay with the app.
        if (_blocked && store != null) Positioned.fill(child: ScaffoldMessenger(child: _UpdateRequiredScreen(store))),
      ],
    );
  }
}

class _UpdateRequiredScreen extends StatelessWidget {
  const _UpdateRequiredScreen(this.store);

  final AppStore store;

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
                Center(
                  child: Image.asset('assets/icons/app.png', width: 88, height: 88, excludeFromSemantics: true),
                ),
                const SizedBox(height: Space.l),
                BalancedText(l10n.updateRequiredTitle, style: AppText.title2),
                const SizedBox(height: Space.s),
                BalancedText(l10n.updateRequiredBody, style: AppText.body.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: Space.xl),
                PrimaryButton(
                  label: l10n.updateRequiredOpen(store.label),
                  onPressed: () => launchUrl(store.page, mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import 'add_to_home.dart';
import 'church_logo.dart';
import 'welcome_screen.dart';
import 'your_name.dart';
import '../../state/session.dart';

/// Churches asked to join from this device, per account, so the welcome
/// page can say so once the church URL is closed. Only remembered: how each
/// stands is the church's to say (AskedToJoinRows, welcome_screen.dart).
class AskedToJoin extends Notifier<Set<String>> {
  String get _key => 'asked_to_join_${ref.read(uidProvider)}';

  @override
  Set<String> build() {
    ref.watch(uidProvider);
    return (ref.read(prefsProvider).getStringList(_key) ?? const []).toSet();
  }

  void add(String churchId) => _save({...state, churchId});

  void remove(String churchId) {
    if (state.contains(churchId)) _save({...state}..remove(churchId));
  }

  void _save(Set<String> next) {
    state = next;
    ref.read(prefsProvider).setStringList(_key, next.toList());
  }
}

final askedToJoinProvider = NotifierProvider<AskedToJoin, Set<String>>(AskedToJoin.new);

/// Where a church URL (/c/ID) lands for someone who is not a member of
/// that church: which church it is and how to join, by asking to (申請加入,
/// #88) or with an invite code. Members never see it; the router opens
/// their church straight away (router.dart).
///
/// A home-screen shortcut opens the church URL every launch, so the
/// shortcut's church is the one shown; switching in the app works as usual
/// afterwards.
class ChurchEntryScreen extends ConsumerWidget {
  const ChurchEntryScreen({super.key, required this.churchId});

  final String churchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(membershipsProvider);
    if (!memberships.hasValue && !memberships.hasError) return const Scaffold(body: SizedBox.expand());
    return _NotMember(churchId: churchId, hasChurch: (memberships.value ?? const []).isNotEmpty);
  }
}

class _NotMember extends ConsumerStatefulWidget {
  const _NotMember({required this.churchId, required this.hasChurch});

  final String churchId;
  final bool hasChurch;

  @override
  ConsumerState<_NotMember> createState() => _NotMemberState();
}

class _NotMemberState extends ConsumerState<_NotMember> {
  bool _busy = false;
  String? _typedName;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back in the app, how the request stands may have changed: turned down
    // meanwhile. Being let in shows through the memberships.
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(churchPreviewProvider(widget.churchId)));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Asks to join as [name], with what they want the admin to know.
  Future<void> _ask(ChurchPreview church, String name) async {
    final l10n = L10n.of(context);
    final note = await promptText(
      context,
      title: l10n.askToJoinTitle(church.name),
      label: l10n.joinNoteLabel,
      hint: l10n.joinNoteHint,
      maxLength: TextLimits.joinNote,
      maxLines: 3,
      action: l10n.askToJoin,
      optional: true,
    );
    if (note == null || !mounted) return;
    await _run(
      () async {
        await saveJoiningName(ref, name);
        await ref.read(backendProvider).cloud.requestToJoin(widget.churchId, note: note);
        ref.read(telemetryProvider).logEvent('join_request');
        ref.read(askedToJoinProvider.notifier).add(widget.churchId);
      },
      done: l10n.joinRequestSent,
    );
  }

  Future<void> _withdraw() => _run(
    () async {
      await ref.read(backendProvider).cloud.withdrawJoinRequest(widget.churchId);
      ref.read(askedToJoinProvider.notifier).remove(widget.churchId);
    },
    done: L10n.of(context).joinRequestWithdrawn,
  );

  Future<void> _run(Future<void> Function() action, {required String done}) async {
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(churchPreviewProvider(widget.churchId));
      if (mounted) showToast(context, done);
    } catch (e) {
      if (!mounted) return;
      final unverified = e is CloudException && e.code == CloudErrorCode.unverifiedEmail;
      showToast(context, unverified ? l10n.joinVerifyFirst : errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final churchId = widget.churchId;
    final preview = ref.watch(churchPreviewProvider(churchId));
    final name = joiningName(ref, _typedName);
    // Asking waits for the email to be verified, said before a note is typed.
    final verified = ref.watch(authUserProvider.select((u) => u.value?.verified ?? false));
    // Let in while this page is open: on into the church, as after an
    // invite. Someone in no church gets there by the router already.
    ref.listen(membershipsProvider, (_, next) {
      if (!widget.hasChurch || !(next.value ?? const []).any((m) => m.churchId == churchId)) return;
      ref.read(selectedChurchProvider.notifier).select(churchId);
      final name = preview.value?.name;
      if (name != null) showToast(context, l10n.joined(name));
      goAfterJoining(context, ref, churchId);
    });
    // Somewhere to go next: home for members of another church, the invite
    // code page for everyone else.
    Widget next({required bool primary}) => widget.hasChurch
        ? SecondaryButton(label: l10n.goHome, expand: true, onPressed: () => context.go('/home'))
        : primary
        ? PrimaryButton(label: l10n.enterInviteCode, onPressed: () => context.go('/welcome/join'))
        : SecondaryButton(label: l10n.enterInviteCode, expand: true, onPressed: () => context.go('/welcome/join'));
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: preview.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => EmptyState(
            message: e is CloudException && e.code == CloudErrorCode.notFound
                ? l10n.churchNotFound
                : errorText(l10n, e),
            actionLabel: l10n.goHome,
            onAction: () => context.go('/home'),
          ),
          data: (church) {
            // Asked before this device remembered it (or on another one):
            // the welcome page says so from now on.
            if (church.joinRequest == JoinRequestState.pending && !ref.read(askedToJoinProvider).contains(churchId)) {
              WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(askedToJoinProvider.notifier).add(churchId));
            }
            final canAsk = church.takesJoinRequests && church.joinRequest != JoinRequestState.pending;
            final message = switch (church.joinRequest) {
              // Waiting on a church that stopped taking requests: nobody
              // can let them in now (#88).
              JoinRequestState.pending when !church.takesJoinRequests => l10n.churchEntryNotMember,
              JoinRequestState.pending => l10n.joinRequestPending,
              JoinRequestState.rejected => l10n.joinRequestRejected,
              null => church.takesJoinRequests ? l10n.churchEntryCanAsk : l10n.churchEntryNotMember,
            };
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(Space.l),
                  children: [
                    if (canAsk) const VerifyEmailBanner(),
                    ChurchLogo(url: church.logoUrl),
                    BalancedText(church.name, style: AppText.title),
                    const SizedBox(height: Space.s),
                    BalancedText(message, style: AppText.body.copyWith(color: c.secondaryLabel)),
                    const SizedBox(height: Space.xl),
                    if (canAsk) ...[
                      YourNameField(
                        typed: _typedName,
                        enabled: verified,
                        onChanged: (v) => setState(() => _typedName = v),
                      ),
                      const SizedBox(height: Space.l),
                      PrimaryButton(
                        label: church.joinRequest == JoinRequestState.rejected ? l10n.askAgain : l10n.askToJoin,
                        busy: _busy,
                        onPressed: name.isEmpty || !verified ? null : () => _ask(church, name),
                      ),
                      const SizedBox(height: Space.s),
                      next(primary: false),
                    ] else if (church.joinRequest == JoinRequestState.pending) ...[
                      SecondaryButton(
                        label: l10n.withdrawJoinRequest,
                        expand: true,
                        onPressed: _busy ? null : _withdraw,
                      ),
                      next(primary: false),
                    ] else
                      next(primary: true),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

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

  /// Asks to join, with what they want the admin to know.
  Future<void> _ask(ChurchPreview church) async {
    final l10n = L10n.of(context);
    final note = await showAdaptiveDialog<String>(
      context: context,
      builder: (context) => _AskDialog(churchName: church.name),
    );
    if (note == null || !mounted) return;
    await _run(
      () => ref.read(backendProvider).cloud.requestToJoin(widget.churchId, note: note),
      done: l10n.joinRequestSent,
    );
  }

  Future<void> _withdraw() => _run(
    () => ref.read(backendProvider).cloud.withdrawJoinRequest(widget.churchId),
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
            final canAsk = church.takesRequests && church.request != JoinRequestState.pending;
            final message = switch (church.request) {
              JoinRequestState.pending => l10n.joinRequestPending,
              JoinRequestState.rejected => l10n.joinRequestRejected,
              null => church.takesRequests ? l10n.churchEntryCanAsk : l10n.churchEntryNotMember,
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
                      PrimaryButton(
                        label: church.request == JoinRequestState.rejected ? l10n.askAgain : l10n.askToJoin,
                        busy: _busy,
                        onPressed: () => _ask(church),
                      ),
                      const SizedBox(height: Space.s),
                      next(primary: false),
                    ] else if (church.request == JoinRequestState.pending) ...[
                      SecondaryButton(
                        label: l10n.withdrawJoinRequest,
                        expand: true,
                        onPressed: _busy ? null : _withdraw,
                      ),
                      if (widget.hasChurch) next(primary: false),
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

/// What someone asking to join tells the admin, optional. Returns it
/// trimmed, or null when cancelled.
class _AskDialog extends StatefulWidget {
  const _AskDialog({required this.churchName});

  final String churchName;

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.askToJoinTitle(widget.churchName)),
      content: TextField(
        controller: _note,
        autofocus: true,
        maxLength: TextLimits.joinNote,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(labelText: l10n.joinNoteLabel, hintText: l10n.joinNoteHint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(onPressed: () => Navigator.pop(context, _note.text.trim()), child: Text(l10n.sendJoinRequest)),
      ],
    );
  }
}

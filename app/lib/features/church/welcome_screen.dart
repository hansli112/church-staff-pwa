import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/limits.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../common/errors.dart';
import 'claims.dart';
import 'links.dart';

/// For someone signed in who belongs to no church yet. Most people arrive
/// through an invite link and never see this; the rest either have a code
/// or are starting a church.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Also under the code and new-church pages opened from 切換教會, where
    // going back lands here: blank for someone in a church (a swipe back
    // shows it), and back to 我的 once it is the top page, since a pop is
    // not redirected.
    if (ref.watch(appStageProvider) == AppStage.ready) {
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/me');
        });
      }
      return const Scaffold();
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
                const VerifyEmailBanner(),
                const PendingClaimsCard(),
                Text(
                  l10n.welcomeTitle,
                  textAlign: TextAlign.center,
                  style: AppText.title,
                ),
                const SizedBox(height: Space.s),
                Text(
                  l10n.welcomeBody,
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: c.secondaryLabel),
                ),
                const SizedBox(height: Space.xl),
                PrimaryButton(
                  label: l10n.enterInviteCode,
                  onPressed: () => context.push('/welcome/join'),
                ),
                const SizedBox(height: Space.s),
                SecondaryButton(
                  label: l10n.createChurch,
                  expand: true,
                  onPressed: () => context.push('/welcome/create'),
                ),
                const SizedBox(height: Space.xl),
                SecondaryButton(
                  label: l10n.signOut,
                  expand: true,
                  onPressed: () => signOut(ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks email sign-ups to click the link in the verification email. Shows
/// nothing for Google and Apple accounts, or once verified.
class VerifyEmailBanner extends ConsumerStatefulWidget {
  const VerifyEmailBanner({super.key});

  @override
  ConsumerState<VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends ConsumerState<VerifyEmailBanner> {
  bool _busy = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back from the email's link: look again without being asked.
    _lifecycle = AppLifecycleListener(onResume: _recheck);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _recheck() {
    final user = ref.read(authUserProvider).value;
    if (user != null && !user.verified) ref.read(backendProvider).auth.reload().ignore();
  }

  Future<void> _check() async {
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).auth.reload();
      final user = ref.read(backendProvider).auth.currentUser;
      if (mounted && !(user?.verified ?? false)) {
        showToast(context, l10n.verifyStill);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final l10n = L10n.of(context);
    try {
      await ref.read(backendProvider).auth.sendEmailVerification();
      if (mounted) showToast(context, l10n.verifyResent);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    if (user == null || user.verified) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.xl),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(Radii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.verifyEmailTitle, style: AppText.headline),
          const SizedBox(height: Space.xs),
          Text(l10n.verifyEmailBody(user.email), style: AppText.subheadline),
          const SizedBox(height: Space.s),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              SecondaryButton(label: l10n.verifyResend, onPressed: _resend),
              SecondaryButton(
                label: l10n.verifyDone,
                onPressed: _busy ? null : _check,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Typing an invite code by hand; it opens the same join page as a link.
class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({super.key});

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _next() {
    final text = _code.text.trim();
    if (text.isEmpty) return;
    // Accept a whole pasted link too.
    final fromLink = inviteCodeIn(Uri.tryParse(text)?.path ?? '');
    context.push('/welcome/join/${fromLink ?? text.toUpperCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.enterInviteCode)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            style: AppText.title3.copyWith(letterSpacing: 2),
            decoration: InputDecoration(hintText: l10n.inviteCode),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _next(),
          ),
          const SizedBox(height: Space.l),
          PrimaryButton(
            label: l10n.next,
            onPressed: _code.text.trim().isEmpty ? null : _next,
          ),
        ],
      ),
    );
  }
}

/// Starting a new church. The backend checks the name is not taken.
class CreateChurchScreen extends ConsumerStatefulWidget {
  const CreateChurchScreen({super.key});

  @override
  ConsumerState<CreateChurchScreen> createState() => _CreateChurchScreenState();
}

class _CreateChurchScreenState extends ConsumerState<CreateChurchScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _duplicate = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _duplicate = false;
    });
    try {
      final cid = await ref.read(backendProvider).cloud.createChurch(name);
      ref.read(selectedChurchProvider.notifier).select(cid);
      Haptics.success();
      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(L10n.of(context), e);
        _duplicate = e is CloudException && e.code == CloudErrorCode.duplicateName;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final verified = ref.watch(
      authUserProvider.select((u) => u.value?.verified ?? false),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.createChurch)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          const VerifyEmailBanner(),
          TextField(
            controller: _name,
            autofocus: verified,
            enabled: verified,
            maxLength: TextLimits.churchName,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: l10n.churchName,
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.s),
            Text(
              _error!,
              style: AppText.subheadline.copyWith(color: c.destructive),
            ),
            if (_duplicate)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SecondaryButton(
                  label: l10n.contactUs,
                  onPressed: () => launchUrl(Uri.parse(supportUrl)),
                ),
              ),
          ],
          const SizedBox(height: Space.l),
          PrimaryButton(
            label: l10n.create,
            busy: _busy,
            onPressed: verified && _name.text.trim().isNotEmpty ? _create : null,
          ),
          const SizedBox(height: Space.xl),
          SecondaryButton(
            label: l10n.moveFromSelfHost,
            expand: true,
            onPressed: () => context.push('/welcome/move'),
          ),
        ],
      ),
    );
  }
}
